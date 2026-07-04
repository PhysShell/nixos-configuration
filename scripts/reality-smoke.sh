#!/usr/bin/env bash
set -euo pipefail

VPS_SSH="${VPS_SSH:-root@66.245.220.84}"
SSH_OPTS="${SSH_OPTS:--F /dev/null -i ./vultr_vps_relay_china -o IdentitiesOnly=yes}"
SERVER_IP="${SERVER_IP:-66.245.220.84}"
REALITY_SERVER_NAME="${REALITY_SERVER_NAME:-www.yahoo.com}"
LOCAL_SOCKS="${LOCAL_SOCKS:-127.0.0.1:20809}"
IP_CHECK_URL="${IP_CHECK_URL:-https://ifconfig.co}"
TEST_URLS="${TEST_URLS:-https://ifconfig.co http://ifconfig.co/ip https://icanhazip.com http://1.1.1.1/cdn-cgi/trace}"
XRAY_BIN="${XRAY_BIN:-}"

declare -a ssh_opts=()
# shellcheck disable=SC2206
ssh_opts=( $SSH_OPTS )

creds=$(ssh "${ssh_opts[@]}" "$VPS_SSH" 'cat /root/vless-reality.env')
VLESS_UUID=$(printf '%s\n' "$creds" | sed -n 's/^VLESS_UUID=//p')
REALITY_PUBLIC=$(printf '%s\n' "$creds" | sed -n 's/^REALITY_PUBLIC=//p')
SHORT_ID=$(printf '%s\n' "$creds" | sed -n 's/^SHORT_ID=//p')
REALITY_SERVER_NAME=$(printf '%s\n' "$creds" | sed -n 's/^REALITY_SERVER_NAME=//p' | tail -n1)

: "${VLESS_UUID:?missing VLESS_UUID}"
: "${REALITY_PUBLIC:?missing REALITY_PUBLIC}"
: "${SHORT_ID:?missing SHORT_ID}"
: "${REALITY_SERVER_NAME:?missing REALITY_SERVER_NAME}"

if [[ -z "$XRAY_BIN" ]]; then
  XRAY_BIN=$(command -v xray || true)
fi

if [[ -z "$XRAY_BIN" ]]; then
  XRAY_BIN=$(find /nix/store -maxdepth 3 -type f -path '*/bin/xray' | sort | tail -n 1)
fi

if [[ -z "$XRAY_BIN" ]]; then
  echo "missing xray client; run: nix shell nixpkgs#xray" >&2
  exit 1
fi

host=${LOCAL_SOCKS%:*}
port=${LOCAL_SOCKS##*:}
tmp=$(mktemp --suffix=.json)
log=$(mktemp)
chmod 600 "$tmp" "$log"
trap 'rm -f "$tmp" "$log"' EXIT

cat > "$tmp" <<JSON
{
  "log": {
    "loglevel": "debug"
  },
  "inbounds": [
    {
      "tag": "socks-in",
      "listen": "$host",
      "port": $port,
      "protocol": "socks",
      "settings": {
        "auth": "noauth",
        "udp": true
      }
    }
  ],
  "outbounds": [
    {
      "tag": "proxy",
      "protocol": "vless",
      "settings": {
        "vnext": [
          {
            "address": "$SERVER_IP",
            "port": 443,
            "users": [
              {
                "id": "$VLESS_UUID",
                "encryption": "none"
              }
            ]
          }
        ]
      },
      "streamSettings": {
        "network": "raw",
        "security": "reality",
        "realitySettings": {
          "serverName": "$REALITY_SERVER_NAME",
          "fingerprint": "chrome",
          "password": "$REALITY_PUBLIC",
          "shortId": "$SHORT_ID",
          "spiderX": "/"
        }
      }
    }
  ]
}
JSON

timeout 30 "$XRAY_BIN" run -c "$tmp" >"$log" 2>&1 &
pid=$!
sleep 2

if ! kill -0 "$pid" 2>/dev/null; then
  printf 'local xray client failed to start\n\n== xray client log ==\n' >&2
  cat "$log" >&2
  exit 1
fi

for url in $TEST_URLS; do
  printf '\n== curl %s ==\n' "$url"
  curl -4fsS --max-time 12 -x "socks5h://$LOCAL_SOCKS" "$url" 2>&1 || true
done
kill "$pid" 2>/dev/null || true
wait "$pid" 2>/dev/null || true

printf '\n== xray client log ==\n'
tail -n 160 "$log"
printf '\n== xray server journal ==\n'
timeout 15 ssh "${ssh_opts[@]}" "$VPS_SSH" 'journalctl -u xray -n 100 --no-pager' || true
