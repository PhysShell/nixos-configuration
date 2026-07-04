#!/usr/bin/env bash
set -euo pipefail

VPS_SSH="${VPS_SSH:-root@66.245.220.84}"
SSH_OPTS="${SSH_OPTS:--F /dev/null -i ./vultr_vps_relay_china -o IdentitiesOnly=yes}"
SERVER_IP="${SERVER_IP:-66.245.220.84}"
REALITY_SERVER_NAME="${REALITY_SERVER_NAME:-www.yahoo.com}"
REALITY_TARGET="${REALITY_TARGET:-$REALITY_SERVER_NAME:443}"
XRAY_CONFIG="${XRAY_CONFIG:-/usr/local/etc/xray/config.json}"
MARK_DEC="${MARK_DEC:-102}"

declare -a ssh_opts=()
# shellcheck disable=SC2206
ssh_opts=( $SSH_OPTS )

ssh "${ssh_opts[@]}" "$VPS_SSH" \
  "SERVER_IP='$SERVER_IP' REALITY_SERVER_NAME='$REALITY_SERVER_NAME' REALITY_TARGET='$REALITY_TARGET' XRAY_CONFIG='$XRAY_CONFIG' MARK_DEC='$MARK_DEC' bash -s" <<'REMOTE'
set -euo pipefail

CRED_FILE=/root/vless-reality.env
CLIENT_FILE=/root/vless-reality-client-hiddify.txt
CLIENT_RAW_FILE=/root/vless-reality-client-raw.txt
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
REQUESTED_REALITY_SERVER_NAME=$REALITY_SERVER_NAME
REQUESTED_REALITY_TARGET=$REALITY_TARGET

cp -a "$XRAY_CONFIG" "/root/xray-config.before-reality-reset.$STAMP.bak"

if [ -f "$CRED_FILE" ]; then
  # shellcheck disable=SC1090
  . "$CRED_FILE"
fi

REALITY_SERVER_NAME=$REQUESTED_REALITY_SERVER_NAME
REALITY_TARGET=$REQUESTED_REALITY_TARGET

if [ -z "${VLESS_UUID:-}" ]; then
  VLESS_UUID=$(xray uuid)
fi

if [ -z "${REALITY_PRIVATE:-}" ] || [ -z "${REALITY_PUBLIC:-}" ]; then
  key_output=$(xray x25519)
  REALITY_PRIVATE=$(printf '%s\n' "$key_output" | awk -F': *' '/^PrivateKey/ { print $2; exit }')
  REALITY_PUBLIC=$(printf '%s\n' "$key_output" | awk -F': *' '/PublicKey/ { print $2; exit }')
fi

if [ -z "${SHORT_ID:-}" ]; then
  SHORT_ID=$(openssl rand -hex 8)
fi

: "${VLESS_UUID:?missing VLESS_UUID}"
: "${REALITY_PRIVATE:?missing REALITY_PRIVATE}"
: "${REALITY_PUBLIC:?missing REALITY_PUBLIC}"
: "${SHORT_ID:?missing SHORT_ID}"

cat > "$CRED_FILE" <<EOF
VLESS_UUID=$VLESS_UUID
REALITY_PRIVATE=$REALITY_PRIVATE
REALITY_PUBLIC=$REALITY_PUBLIC
SHORT_ID=$SHORT_ID
REALITY_SERVER_NAME=$REALITY_SERVER_NAME
EOF
chmod 600 "$CRED_FILE"

cat > "$XRAY_CONFIG" <<EOF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "tag": "socks-test",
      "listen": "127.0.0.1",
      "port": 10808,
      "protocol": "socks",
      "settings": {
        "auth": "noauth",
        "udp": true
      }
    },
    {
      "tag": "vless-reality",
      "listen": "0.0.0.0",
      "port": 443,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "$VLESS_UUID",
            "email": "physshell"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "raw",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "target": "$REALITY_TARGET",
          "xver": 0,
          "serverNames": [ "$REALITY_SERVER_NAME" ],
          "privateKey": "$REALITY_PRIVATE",
          "shortIds": [ "$SHORT_ID" ]
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": [ "http", "tls", "quic" ]
      }
    }
  ],
  "outbounds": [
    {
      "tag": "home-out",
      "protocol": "freedom",
      "settings": {
        "domainStrategy": "UseIPv4"
      },
      "streamSettings": {
        "sockopt": {
          "mark": $MARK_DEC
        }
      }
    }
  ]
}
EOF
chmod 644 "$XRAY_CONFIG"

systemctl restart xray
systemctl is-active xray
for _ in $(seq 1 20); do
  if ss -ltn | grep -q ':443' && ss -ltn | grep -q ':10808'; then
    break
  fi
  sleep 0.25
done

cat > "$CLIENT_FILE" <<EOF
vless://$VLESS_UUID@$SERVER_IP:443?encryption=none&security=reality&sni=$REALITY_SERVER_NAME&fp=chrome&pbk=$REALITY_PUBLIC&sid=$SHORT_ID&type=tcp&spx=%2F#vultr-home-exit-yahoo
EOF
chmod 600 "$CLIENT_FILE"

cat > "$CLIENT_RAW_FILE" <<EOF
vless://$VLESS_UUID@$SERVER_IP:443?encryption=none&security=reality&sni=$REALITY_SERVER_NAME&fp=chrome&pbk=$REALITY_PUBLIC&sid=$SHORT_ID&type=raw&spx=%2F#vultr-home-exit-yahoo-raw
EOF
chmod 600 "$CLIENT_RAW_FILE"

echo "== Xray listeners =="
ss -ltnp | grep -E ':443|10808' || true
echo "== SOCKS smoke =="
curl -4fsS --max-time 15 -x socks5h://127.0.0.1:10808 https://ifconfig.co || true
echo "== Hiddify link =="
timeout 5 cat "$CLIENT_FILE"
echo
echo "== Raw-type fallback link =="
timeout 5 cat "$CLIENT_RAW_FILE"
echo
echo "== Journal tail =="
timeout 10 journalctl -u xray -n 30 --no-pager || true
REMOTE
