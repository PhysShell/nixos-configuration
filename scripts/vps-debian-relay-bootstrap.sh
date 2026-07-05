#!/usr/bin/env bash
set -euo pipefail

VPS_SSH="${VPS_SSH:-root@91.99.95.47}"
SSH_OPTS="${SSH_OPTS:--F /dev/null -i ./hetzner_relay -o IdentitiesOnly=yes}"

VPS_WG_IFACE="${VPS_WG_IFACE:-wg-vps}"
VPS_WG_ADDR="${VPS_WG_ADDR:-10.66.66.1/24}"
HOME_WG_PUB="${HOME_WG_PUB:-Wo8dr92bByaCv+/GmmRFH1lERKD9dW7Znt+HkrV9jkA=}"
WG_PORT="${WG_PORT:-51820}"
ROUTE_TABLE="${ROUTE_TABLE:-100}"
ROUTE_PREF="${ROUTE_PREF:-10066}"
ROUTE_MARK="${ROUTE_MARK:-0x66}"
MARK_DEC="${MARK_DEC:-102}"

declare -a ssh_opts=()
# shellcheck disable=SC2206
ssh_opts=( $SSH_OPTS )

sq() {
  local value=${1//\'/\'\\\'\'}
  printf "'%s'" "$value"
}

ssh "${ssh_opts[@]}" "$VPS_SSH" \
  "VPS_WG_IFACE=$(sq "$VPS_WG_IFACE") VPS_WG_ADDR=$(sq "$VPS_WG_ADDR") HOME_WG_PUB=$(sq "$HOME_WG_PUB") WG_PORT=$(sq "$WG_PORT") ROUTE_TABLE=$(sq "$ROUTE_TABLE") ROUTE_PREF=$(sq "$ROUTE_PREF") ROUTE_MARK=$(sq "$ROUTE_MARK") MARK_DEC=$(sq "$MARK_DEC") bash -s" <<'REMOTE'
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

if ! command -v apt-get >/dev/null 2>&1; then
  echo "This bootstrap script expects a Debian/Ubuntu-like VPS with apt-get." >&2
  exit 1
fi

apt-get update
apt-get install -y \
  ca-certificates \
  curl \
  iproute2 \
  iptables \
  jq \
  openssl \
  tcpdump \
  ufw \
  unzip \
  wireguard-tools

install -d -m 0700 /etc/wireguard

if [ ! -f "/etc/wireguard/$VPS_WG_IFACE.key" ]; then
  umask 077
  wg genkey > "/etc/wireguard/$VPS_WG_IFACE.key"
fi

VPS_WG_PRIVATE=$(cat "/etc/wireguard/$VPS_WG_IFACE.key")
VPS_WG_PUBLIC=$(printf '%s' "$VPS_WG_PRIVATE" | wg pubkey)

cat > "/etc/wireguard/$VPS_WG_IFACE.conf" <<EOF
[Interface]
Address = $VPS_WG_ADDR
ListenPort = $WG_PORT
PrivateKey = $VPS_WG_PRIVATE
Table = off
PostUp = ip route replace default dev %i table $ROUTE_TABLE; ip rule del pref $ROUTE_PREF fwmark $ROUTE_MARK lookup $ROUTE_TABLE 2>/dev/null || true; ip rule add pref $ROUTE_PREF fwmark $ROUTE_MARK lookup $ROUTE_TABLE; ip -6 route replace unreachable default table $ROUTE_TABLE; ip -6 rule del pref $ROUTE_PREF fwmark $ROUTE_MARK lookup $ROUTE_TABLE 2>/dev/null || true; ip -6 rule add pref $ROUTE_PREF fwmark $ROUTE_MARK lookup $ROUTE_TABLE
PostDown = ip rule del pref $ROUTE_PREF fwmark $ROUTE_MARK lookup $ROUTE_TABLE 2>/dev/null || true; ip route del default dev %i table $ROUTE_TABLE 2>/dev/null || true; ip -6 rule del pref $ROUTE_PREF fwmark $ROUTE_MARK lookup $ROUTE_TABLE 2>/dev/null || true; ip -6 route del unreachable default table $ROUTE_TABLE 2>/dev/null || true

[Peer]
PublicKey = $HOME_WG_PUB
AllowedIPs = 0.0.0.0/0
EOF
chmod 600 "/etc/wireguard/$VPS_WG_IFACE.conf"

cat > /etc/sysctl.d/99-relay.conf <<'EOF'
net.ipv4.ip_forward = 1
EOF
sysctl -w net.ipv4.ip_forward=1 >/dev/null

ufw allow 22/tcp
ufw allow 443/tcp
ufw allow "$WG_PORT/udp"
ufw --force enable

systemctl enable "wg-quick@$VPS_WG_IFACE"
systemctl restart "wg-quick@$VPS_WG_IFACE"

if ! command -v xray >/dev/null 2>&1; then
  bash -c "$(curl -fsSL https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
fi

install -d -m 0755 /usr/local/etc/xray
if [ ! -f /usr/local/etc/xray/config.json ]; then
  cat > /usr/local/etc/xray/config.json <<'EOF'
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct"
    }
  ]
}
EOF
fi

install -d -m 0755 /etc/systemd/system/xray.service.d
cat > /etc/systemd/system/xray.service.d/10-relay.conf <<'EOF'
[Service]
User=root
Group=root
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_SETUID CAP_SETGID
EOF

systemctl daemon-reload
systemctl enable xray

echo "== WireGuard =="
wg show "$VPS_WG_IFACE"
echo "VPS_WG_PUBLIC=$VPS_WG_PUBLIC"
echo "== Policy route =="
ip rule show | grep "$ROUTE_PREF" || true
ip route show table "$ROUTE_TABLE" || true
echo "== Listeners =="
ss -lunp | grep ":$WG_PORT" || true
systemctl is-active "wg-quick@$VPS_WG_IFACE"
systemctl is-enabled "wg-quick@$VPS_WG_IFACE"
echo "== Xray =="
xray version | head -n 1
systemctl status xray --no-pager -n 0 || true
REMOTE
