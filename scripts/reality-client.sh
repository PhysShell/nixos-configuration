#!/usr/bin/env bash
set -euo pipefail

VPS_SSH="${VPS_SSH:-root@91.99.95.47}"
SSH_OPTS="${SSH_OPTS:--F /dev/null -i ./hetzner_relay -o IdentitiesOnly=yes}"
default_server_ip=${VPS_SSH#*@}
default_server_ip=${default_server_ip%%:*}
SERVER_IP="${SERVER_IP:-$default_server_ip}"
SERVER_PORT="${SERVER_PORT:-443}"
LOCAL_SOCKS="${LOCAL_SOCKS:-127.0.0.1:20809}"
LOGLEVEL="${LOGLEVEL:-warning}"
XRAY_BIN="${XRAY_BIN:-}"

usage() {
  cat <<'USAGE'
Usage:
  nix develop -c ./scripts/reality-client.sh
  ./scripts/reality-client.sh

Starts a local SOCKS5 proxy that forwards traffic through:
  local app -> 127.0.0.1:20809 -> VPS Reality -> WireGuard -> home exit

Useful variables:
  VPS_SSH       SSH target with /root/vless-reality.env, default: root@91.99.95.47
  SSH_OPTS      SSH options, default: "-F /dev/null -i ./hetzner_relay -o IdentitiesOnly=yes"
  SERVER_IP     Reality server IP, default: host part of VPS_SSH
  SERVER_PORT   Reality server port, default: 443
  LOCAL_SOCKS   Local SOCKS listener, default: 127.0.0.1:20809
  LOGLEVEL      Xray loglevel, default: warning

Test while it is running:
  curl -x socks5h://127.0.0.1:20809 https://api.ipify.org
USAGE
}

case "${1:-}" in
  -h|--help)
    usage
    exit 0
    ;;
esac

declare -a ssh_opts=()
# shellcheck disable=SC2206
ssh_opts=( $SSH_OPTS )

if [[ -z "$XRAY_BIN" ]]; then
  XRAY_BIN=$(command -v xray || true)
fi

if [[ -z "$XRAY_BIN" ]]; then
  XRAY_BIN=$(find /nix/store -maxdepth 3 -type f -path '*/bin/xray' | sort | tail -n 1)
fi

if [[ -z "$XRAY_BIN" ]]; then
  echo "missing xray client; run via: nix develop -c ./scripts/reality-client.sh" >&2
  exit 1
fi

creds=$(ssh "${ssh_opts[@]}" "$VPS_SSH" 'cat /root/vless-reality.env')
VLESS_UUID=$(printf '%s\n' "$creds" | sed -n 's/^VLESS_UUID=//p')
REALITY_PUBLIC=$(printf '%s\n' "$creds" | sed -n 's/^REALITY_PUBLIC=//p')
SHORT_ID=$(printf '%s\n' "$creds" | sed -n 's/^SHORT_ID=//p')
REALITY_SERVER_NAME=$(printf '%s\n' "$creds" | sed -n 's/^REALITY_SERVER_NAME=//p' | tail -n1)

: "${VLESS_UUID:?missing VLESS_UUID}"
: "${REALITY_PUBLIC:?missing REALITY_PUBLIC}"
: "${SHORT_ID:?missing SHORT_ID}"
: "${REALITY_SERVER_NAME:?missing REALITY_SERVER_NAME}"

host=${LOCAL_SOCKS%:*}
port=${LOCAL_SOCKS##*:}
tmpdir=$(mktemp -d)
config=$tmpdir/reality-client.json
trap 'rm -rf "$tmpdir"' EXIT
chmod 700 "$tmpdir"

cat > "$config" <<JSON
{
  "log": {
    "loglevel": "$LOGLEVEL"
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
            "port": $SERVER_PORT,
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
chmod 600 "$config"

cat <<EOF
SOCKS5 proxy listening on socks5h://$LOCAL_SOCKS
Reality server: $SERVER_IP:$SERVER_PORT / $REALITY_SERVER_NAME

Test from another terminal:
  curl -x socks5h://$LOCAL_SOCKS https://api.ipify.org

Stop with Ctrl-C.
EOF

exec "$XRAY_BIN" run -c "$config"
