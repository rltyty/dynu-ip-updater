# dynu-ip-updater
An IP updater for Dynu DDNS

## What Dynu provides

### [Update in traditional way][0]

```bash
curl -fsS \
    'http://api.dynu.com/nic/update?
hostname=<domain_name>&password=<ip_update_password_sha256_hash>&username=<user>&myip=<wan_ip>'
```

### Update using [REST API][1]

#### Service URL

```
https://api.dynu.com/v2
```

#### Get <domain_id> ([GET /dns][2])

```bash
curl -4 -fsS --max-time 15 https://api.dynu.com/v2/dns \
    -H "Accept: application/json" \
    -H "API-Key: <api_key>"
```

#### Get domain status ([GET /dns/<id>][3])

```bash
curl -4 -fsS --max-time 15 https://api.dynu.com/v2/dns/<domain_id> \
    -H "Accept: application/json" \
    -H "API-Key: <api_key>"
```

#### Update IP address ([POST /dns/<id>][4])

Overwrite the domain status with the new <wan_ip> and build up post data.

```bash
curl -4 -fsS --max-time 15 https://api.dynu.com/v2/dns/<domain_id> \
    --header 'Accept: application/json' \
    --header 'API-KEY: API_KEY' \
    --data '{
        "name": <domain_name>,
        "group": current_group,
        "ipv4Address": <wan_ip>,
        "ipv6Address": null,
        "ttl": 120,
        "ipv4": true,
        "ipv6": true,
        "ipv4WildcardAlias": true,
        "ipv6WildcardAlias": true,
        "allowZoneTransfer": false,
        "dnssec": false
    }'
```

## Full-fledged script

### [dynu-update.sh](./dynu-update.sh)

- Running as a cron job

```
0,5,10,15,20,25,30,35,40,45,50,55 * * * * sleep 44 ; /bin/sh $HOME/ddns/dynu-update.sh
```

- Input: a **RECORD** file at the same directory of the script

```txt
DOMAIN_NAME
USER
IP_UPDATE_PASSWORD_SHA256_HASH
```

- Every time when a new <wan_ip> is updated successfully, it is save in
  `/tmp/dynu-last-ip`. Next time the script will compare current <wan_ip>
  with the last updated IP, if no change then exits quietly.

### [dynu-update.api.sh](./dynu-update.api.sh)

- Running as a cron job

```
0,5,10,15,20,25,30,35,40,45,50,55 * * * * sleep 44 ; /bin/sh $HOME/ddns/dynu-update.api.sh
```

- Input: a **RECORD.api** file at the same directory of the script

```txt
DOMAIN_ID
DOMAIN_NAME
API_KEY
```

- Every time it firstly GETs the device domain status on Dynu, if there is a
  discrepancy on the IP address, it will POST the new <wan_ip> to Dynu,
  otherwise exits quietly.

### Get WAN_IP of a device

```bash
curl -4 -fsS --max-time 15 "http://members.3322.org/dyndns/getip"
```

### Logging

Logging in the system log using Unix/Linux **logger** with tag `dynu`.

To view them:

- Debian:    `journalctl -t dynu`
- OpenWrt:   `logread -e dynu`
- macOS:     `log show --style syslog --last 1d --predicate 'process == "logger" AND eventMessage CONTAINS[c] "[dynu]"'`

***NOTE***:
[Unified log on macOS doesn't respect logger tag as a logging field, only keeps
process name and message saved][5]. We have to use them as keywords, like "\[dynu\]"
in this script.

[0]: https://www.dynu.com/DynamicDNS/IP-Update-Protocol
[1]: https://www.dynu.com/Support/API
[2]: https://www.dynu.com/Support/API#/dns/dnsGet
[3]: https://www.dynu.com/Support/API#/dns/dnsIdGet
[4]: https://www.dynu.com/Support/API#/dns/dnsIdPost
[5]: https://eclecticlight.co/2023/01/14/how-to-write-to-the-log-from-a-script

