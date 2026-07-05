#!/usr/bin/env bash
set -euo pipefail

VPS_SSH="${VPS_SSH:-root@66.245.220.84}"
SSH_OPTS="${SSH_OPTS:--F /dev/null -i ./vultr_vps_relay_china -o IdentitiesOnly=yes}"
default_server_ip=${VPS_SSH#*@}
default_server_ip=${default_server_ip%%:*}
SERVER_IP="${SERVER_IP:-$default_server_ip}"
REALITY_SERVER_NAME="${REALITY_SERVER_NAME:-www.yahoo.com}"
REALITY_TARGET="${REALITY_TARGET:-$REALITY_SERVER_NAME:443}"
XRAY_CONFIG="${XRAY_CONFIG:-/usr/local/etc/xray/config.json}"
MARK_DEC="${MARK_DEC:-102}"
ROUTE_TABLE="${ROUTE_TABLE:-100}"
ROUTE_PREF="${ROUTE_PREF:-10066}"
PROFILE_NAME="${PROFILE_NAME:-relay-home-exit-yahoo}"

declare -a ssh_opts=()
# shellcheck disable=SC2206
ssh_opts=( $SSH_OPTS )

ssh "${ssh_opts[@]}" "$VPS_SSH" \
  "SERVER_IP='$SERVER_IP' REALITY_SERVER_NAME='$REALITY_SERVER_NAME' REALITY_TARGET='$REALITY_TARGET' XRAY_CONFIG='$XRAY_CONFIG' MARK_DEC='$MARK_DEC' ROUTE_TABLE='$ROUTE_TABLE' ROUTE_PREF='$ROUTE_PREF' PROFILE_NAME='$PROFILE_NAME' bash -s" <<'REMOTE'
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

MARK_HEX=$(printf '0x%x' "$MARK_DEC")
while ip -6 rule del pref "$ROUTE_PREF" 2>/dev/null; do :; done
ip -6 rule add pref "$ROUTE_PREF" fwmark "$MARK_HEX" lookup "$ROUTE_TABLE"
ip -6 route replace unreachable default table "$ROUTE_TABLE"

cat > "$XRAY_CONFIG" <<EOF
{
  "log": {
    "loglevel": "warning"
  },
  "dns": {
    "servers": [ "10.66.66.2" ],
    "queryStrategy": "UseIPv4"
  },
  "routing": {
    "domainStrategy": "AsIs",
    "rules": [
      {
        "type": "field",
        "network": "tcp,udp",
        "ip": [ "::/1", "8000::/1" ],
        "outboundTag": "block"
      },
      {
        "type": "field",
        "network": "tcp,udp",
        "port": "853",
        "outboundTag": "block"
      },
      {
        "type": "field",
        "network": "udp",
        "port": "443",
        "outboundTag": "block"
      },
      {
        "type": "field",
        "network": "tcp,udp",
        "port": "53",
        "outboundTag": "home-dns"
      }
    ]
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
    },
    {
      "tag": "home-dns",
      "protocol": "freedom",
      "settings": {
        "redirect": "10.66.66.2:53"
      },
      "streamSettings": {
        "sockopt": {
          "mark": $MARK_DEC
        }
      }
    },
    {
      "tag": "block",
      "protocol": "blackhole"
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
vless://$VLESS_UUID@$SERVER_IP:443?encryption=none&security=reality&sni=$REALITY_SERVER_NAME&fp=chrome&pbk=$REALITY_PUBLIC&sid=$SHORT_ID&type=tcp&spx=%2F#$PROFILE_NAME
EOF
chmod 600 "$CLIENT_FILE"

cat > "$CLIENT_RAW_FILE" <<EOF
vless://$VLESS_UUID@$SERVER_IP:443?encryption=none&security=reality&sni=$REALITY_SERVER_NAME&fp=chrome&pbk=$REALITY_PUBLIC&sid=$SHORT_ID&type=raw&spx=%2F#$PROFILE_NAME-raw
EOF
chmod 600 "$CLIENT_RAW_FILE"

echo "== Xray listeners =="
ss -ltnp | grep -E ':443|10808' || true
echo "== Marked IPv6 route =="
ip -6 rule show | grep "$ROUTE_PREF" || true
ip -6 route show table "$ROUTE_TABLE" || true
ip -6 route get 2606:4700:4700::1111 mark "$MARK_HEX" 2>&1 || true
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
