#!/bin/sh

# --------------------------------------------------
# Dynu DDNS updater
# --------------------------------------------------

# Resolve the directory containing this script
case "$0" in
    */*)
        SCRIPT_DIR=${0%/*}
        [ -n "$SCRIPT_DIR" ] || SCRIPT_DIR="/"
        ;;
    *)
        SCRIPT_DIR="."
        ;;
esac

RECORD_FILE="$SCRIPT_DIR/RECORD"
LAST_IP_FILE="/tmp/dynu-last-ip"

IP_CHECK_URL="http://members.3322.org/dyndns/getip"
API_URL="https://api.dynu.com/nic/update"

OS=$(uname -s)

# Log helper
log() {
  case $OS in
    Darwin)
      logger "[dynu] $*"
      ;;
    *)
      logger -t dynu "$*"
      ;;
  esac
}

# NOTE:
# To view the logs
# a. Debian:    `journalctl -t dynu`
# b. OpenWrt:   `logread -e dynu`
# c. macOS:
#     `log show --style syslog --last 1d --predicate 'process == "logger" AND eventMessage CONTAINS[c] "[dynu]"'`
#
#    Limitation: Unified log on macOS doesn't respect logger tag as a logging
#    field, only keeps process name and message saved. We have to use them
#    as keywords, like "[dynu]" for this script.
#    https://eclecticlight.co/2023/01/14/how-to-write-to-the-log-from-a-script

# --------------------------------------------------
# 1. Detect current public IPv4
# --------------------------------------------------

WANIP=$(curl -4 -fsS --max-time 15 "$IP_CHECK_URL") || {
    log "Failed to detect public IPv4 address"
    exit 1
}

[ -n "$WANIP" ] || {
    log "Public IP detection returned an empty response"
    exit 1
}

# --------------------------------------------------
# 2. Compare with last successful IP
# --------------------------------------------------

if [ -f "$LAST_IP_FILE" ]; then
    LAST_IP=$(cat "$LAST_IP_FILE")

    if [ "$WANIP" = "$LAST_IP" ]; then
      # Nothing to update, just exit quietly
      exit 0
    fi
fi

# --------------------------------------------------
# 3. Read credentials from RECORD
# --------------------------------------------------

if [ ! -r "$RECORD_FILE" ]; then
    log "Cannot read DNS record file: $RECORD_FILE"
    exit 1
fi

exec 3< "$RECORD_FILE"

# Read hostname
HOSTNAME=
if ! IFS= read -r HOSTNAME <&3 && [ -z "$HOSTNAME" ]; then
    exec 3<&-
    log "Missing hostname in RECORD"
    exit 1
fi

# Read username
USERNAME=
if ! IFS= read -r USERNAME <&3 && [ -z "$USERNAME" ]; then
    exec 3<&-
    log "Missing username in RECORD"
    exit 1
fi

# Read SHA-256 password hash
PASSWORD_HASH=
if ! IFS= read -r PASSWORD_HASH <&3 && [ -z "$PASSWORD_HASH" ]; then
    exec 3<&-
    log "Missing password hash in RECORD"
    exit 1
fi

# Close RECORD
exec 3<&-

# --------------------------------------------------
# 4. Send update request to Dynu
# --------------------------------------------------

if RESPONSE=$(curl -4 -fsS --max-time 20 --get "$API_URL" \
    --data-urlencode "myip=$WANIP" \
    --data-urlencode "hostname=$HOSTNAME" \
    --data-urlencode "password=$PASSWORD_HASH" \
    --data-urlencode "username=$USERNAME" 2>&1); then

    case "$RESPONSE" in
        good*|nochg*)
            # Continue to save the new IP
            ;;
        *)
            log "Dynu rejected update: $RESPONSE"
            exit 1
            ;;
    esac

else
    log "Dynu API request failed: $RESPONSE"
    exit 1
fi

# --------------------------------------------------
# 5. Save new IP only after successful update
# --------------------------------------------------

STATE_TMP="${LAST_IP_FILE}.$$"

if ! printf '%s\n' "$WANIP" > "$STATE_TMP"; then
    log "Update succeeded but failed to write IP state"
    rm -f "$STATE_TMP"
    exit 1
fi

if ! mv -f "$STATE_TMP" "$LAST_IP_FILE"; then
    log "Update succeeded but failed to save IP state"
    rm -f "$STATE_TMP"
    exit 1
fi

log "DDNS update successful: $HOSTNAME -> $WANIP"

exit 0

