#!/bin/sh

# --------------------------------------------------
# Dynu DDNS updater
# --------------------------------------------------
OS=$(uname -s)
IP_CHECK_URL="http://members.3322.org/dyndns/getip"
DYNU_API_DNS="https://api.dynu.com/v2/dns"

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
RECORD_FILE="$SCRIPT_DIR/RECORD.api"

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

WAN_IP=$(curl -4 -fsS --max-time 15 "$IP_CHECK_URL") || {
    log "Failed to detect public IPv4 address"
    exit 1
}

[ -n "$WAN_IP" ] || {
    log "Public IP detection returned an empty response"
    exit 1
}

# --------------------------------------------------
# 2. Read domain id and credentials from RECORD.api
# --------------------------------------------------

if [ ! -r "$RECORD_FILE" ]; then
    log "Cannot read DNS record file: $RECORD_FILE"
    exit 1
fi

exec 3< "$RECORD_FILE"

DOMAIN_ID=
if ! IFS= read -r DOMAIN_ID <&3 && [ -z "$DOMAIN_ID" ]; then
    exec 3<&-
    log "Failed to retrieve domain id."
    exit 1
fi

DOMAIN_NAME=
if ! IFS= read -r DOMAIN_NAME <&3 && [ -z "$DOMAIN_NAME" ]; then
    exec 3<&-
    log "Failed to retrieve domain name."
    exit 1
fi

API_KEY=
if ! IFS= read -r API_KEY <&3 && [ -z "$API_KEY" ]; then
    exec 3<&-
    log "Failed to retrieve API KEY."
    exit 1
fi

# Close RECORD
exec 3<&-

# --------------------------------------------------
# 3. Get domain IP from Dynu and exit if no change
# --------------------------------------------------

RESPONSE=$(curl -4 -fsS --max-time 15 "$DYNU_API_DNS/$DOMAIN_ID" \
    -H "Accept: application/json" \
    -H "API-Key: $API_KEY") || {
    log "Failed to fetch Dynu domain record."
    exit 1
}

# Validate response and extract IP
DYNU_IP=$(printf '%s' "$RESPONSE" | jq -er \
    --arg host "$DOMAIN_NAME" \
    'select(.statusCode == 200 and .name == $host)
     | .ipv4Address | strings | select(length > 0)') || {
    log "Invalid Dynu response."
    exit 1
}

# Nothing to update, just exit quietly
[ "$WAN_IP" != "$DYNU_IP" ] || exit 0

# --------------------------------------------------
# 4. Send update request to Dynu
# --------------------------------------------------

UPDATE_BODY=$(printf '%s' "$RESPONSE" | jq \
    --arg ip "$WAN_IP" '
    {
        name,
        group,
        ipv4Address: $ip,
        ipv6Address,
        ttl,
        ipv4,
        ipv6,
        ipv4WildcardAlias,
        ipv6WildcardAlias,
        allowZoneTransfer: (.allowZoneTransfer // false),
        dnssec: (.dnssec // false)
    }')

UPDATE_RESPONSE=$(curl -4 -fsS --max-time 15 "$DYNU_API_DNS/$DOMAIN_ID" \
    -H "Accept: application/json" \
    -H "Content-Type: application/json" \
    -H "API-Key: $API_KEY" \
    --data "$UPDATE_BODY") || {
    log "Failed to update IP: $DYNU_IP -> $WAN_IP"
    exit 1
}

# Verify update response
printf '%s' "$UPDATE_RESPONSE" |
    jq -e '.statusCode == 200' >/dev/null || {
    log "Dynu update returned an error"
    exit 1
}

log "DDNS update successful: [$DOMAIN_NAME] $DYNU_IP -> $WAN_IP"

exit 0

