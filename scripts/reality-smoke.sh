#!/usr/bin/env bash
set -euo pipefail

VPS_SSH="${VPS_SSH:-root@66.245.220.84}"
SSH_OPTS="${SSH_OPTS:--F /dev/null -i ./vultr_vps_relay_china -o IdentitiesOnly=yes}"
default_server_ip=${VPS_SSH#*@}
default_server_ip=${default_server_ip%%:*}
SERVER_IP="${SERVER_IP:-$default_server_ip}"
REALITY_SERVER_NAME="${REALITY_SERVER_NAME:-www.yahoo.com}"
LOCAL_SOCKS="${LOCAL_SOCKS:-127.0.0.1:20809}"
IP_CHECK_URL="${IP_CHECK_URL:-https://ifconfig.co}"
IP_CHECK_URLS="${IP_CHECK_URLS:-$IP_CHECK_URL https://api.ipify.org https://ipv4.icanhazip.com https://checkip.amazonaws.com}"
TRACE_URLS="${TRACE_URLS:-https://1.1.1.1/cdn-cgi/trace}"
EXPECT_HOME_IP="${EXPECT_HOME_IP:-}"
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

if [[ -z "$EXPECT_HOME_IP" ]]; then
  for url in $IP_CHECK_URLS; do
    if EXPECT_HOME_IP=$(curl -4fsS --max-time 12 "$url" 2>/dev/null | tr -d '[:space:]') && [[ -n "$EXPECT_HOME_IP" ]]; then
      break
    fi
  done
fi

if [[ -n "$EXPECT_HOME_IP" ]]; then
  printf '\n== expected home public IPv4 ==\n%s\n' "$EXPECT_HOME_IP"
else
  printf '\nwarn: cannot detect expected home public IPv4; set EXPECT_HOME_IP to enforce it\n' >&2
fi

for url in $IP_CHECK_URLS; do
  printf '\n== proxy public IPv4 via %s ==\n' "$url"
  ip=$(curl -4fsS --max-time 12 -x "socks5h://$LOCAL_SOCKS" "$url" 2>&1 | tr -d '[:space:]' || true)
  if [[ -n "$ip" ]]; then
    printf '%s\n' "$ip"
    if [[ -n "$EXPECT_HOME_IP" && "$ip" == "$EXPECT_HOME_IP" ]]; then
      printf 'ok: proxy egress matches expected home IP\n'
    elif [[ -n "$EXPECT_HOME_IP" ]]; then
      printf 'fail: proxy egress %s does not match expected home IP %s\n' "$ip" "$EXPECT_HOME_IP" >&2
    fi
  else
    printf 'warn: empty response from %s\n' "$url" >&2
  fi
done

for url in $TRACE_URLS; do
  printf '\n== proxy trace %s ==\n' "$url"
  curl -4fsSL --max-time 12 -x "socks5h://$LOCAL_SOCKS" "$url" 2>&1 || true
done
kill "$pid" 2>/dev/null || true
wait "$pid" 2>/dev/null || true

printf '\n== xray client log ==\n'
tail -n 160 "$log"
printf '\n== xray server journal ==\n'
timeout 15 ssh "${ssh_opts[@]}" "$VPS_SSH" 'journalctl -u xray -n 100 --no-pager' || true
