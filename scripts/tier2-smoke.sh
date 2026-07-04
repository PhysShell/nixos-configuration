#!/usr/bin/env bash
set -u
set -o pipefail

IP_CHECK_URL="${IP_CHECK_URL:-https://ifconfig.co}"
TIMEOUT="${TIMEOUT:-10}"
PING_COUNT="${PING_COUNT:-3}"
PING_TIMEOUT="${PING_TIMEOUT:-3}"
HANDSHAKE_MAX_AGE="${HANDSHAKE_MAX_AGE:-180}"

VPS_SSH="${VPS_SSH:-}"
SSH_OPTS="${SSH_OPTS:-}"

HOME_WG_IFACE="${HOME_WG_IFACE:-wg-vps}"
VPS_WG_IFACE="${VPS_WG_IFACE:-wg-vps}"
HOME_WG_IP="${HOME_WG_IP:-10.66.66.2}"
VPS_WG_IP="${VPS_WG_IP:-10.66.66.1}"
XRAY_SOCKS="${XRAY_SOCKS:-127.0.0.1:10808}"
EXPECT_HOME_IP="${EXPECT_HOME_IP:-}"
ROUTE_MARK="${ROUTE_MARK:-}"

usage() {
  cat <<'USAGE'
Usage:
  VPS_SSH=root@vps ./scripts/tier2-smoke.sh

Common variables:
  VPS_SSH          SSH target for the VPS, for example root@203.0.113.10
  SSH_OPTS         Extra ssh options, for example "-p 2222 -i ~/.ssh/vps"
  HOME_WG_IFACE    Home WireGuard interface name, default: wg-vps
  VPS_WG_IFACE     VPS WireGuard interface name, default: wg-vps
  HOME_WG_IP       Home tunnel IP, default: 10.66.66.2
  VPS_WG_IP        VPS tunnel IP, default: 10.66.66.1
  XRAY_SOCKS       SOCKS listener on the VPS, default: 127.0.0.1:10808
  EXPECT_HOME_IP   Expected residential public IPv4. Defaults to local curl result.
  ROUTE_MARK       Optional policy-routing fwmark to test, for example 0x66

Acceptance target:
  local curl        -> home IP
  VPS normal curl   -> VPS IP
  VPS Xray SOCKS    -> home IP
USAGE
}

case "${1:-}" in
  -h|--help)
    usage
    exit 0
    ;;
esac

failures=0
warnings=0

declare -a ssh_opts=()
if [[ -n "$SSH_OPTS" ]]; then
  # shellcheck disable=SC2206
  ssh_opts=( $SSH_OPTS )
fi

heading() {
  printf '\n== %s ==\n' "$1"
}

ok() {
  printf 'ok: %s\n' "$1"
}

warn() {
  warnings=$((warnings + 1))
  printf 'warn: %s\n' "$1" >&2
}

fail() {
  failures=$((failures + 1))
  printf 'fail: %s\n' "$1" >&2
}

need() {
  if ! command -v "$1" >/dev/null 2>&1; then
    fail "missing local command: $1"
    return 1
  fi
}

sq() {
  local value=${1//\'/\'\\\'\'}
  printf "'%s'" "$value"
}

remote_sh() {
  if [[ -z "$VPS_SSH" ]]; then
    fail "VPS_SSH is not set; export VPS_SSH=root@your-vps"
    return 1
  fi

  ssh "${ssh_opts[@]}" "$VPS_SSH" "bash -o pipefail -c $(sq "$1")"
}

remote_capture() {
  local output

  if output=$(remote_sh "$1" 2>&1); then
    printf '%s' "$output"
    return 0
  fi

  printf '%s' "$output" >&2
  return 1
}

local_public_ip() {
  curl -4fsS --max-time "$TIMEOUT" "$IP_CHECK_URL" | tr -d '[:space:]'
}

remote_public_ip() {
  remote_sh "curl -4fsS --max-time $(sq "$TIMEOUT") $(sq "$IP_CHECK_URL") | tr -d '[:space:]'"
}

remote_xray_public_ip() {
  remote_sh "curl -4fsS --max-time $(sq "$TIMEOUT") -x $(sq "socks5h://$XRAY_SOCKS") $(sq "$IP_CHECK_URL") | tr -d '[:space:]'"
}

wg_show_local() {
  wg show "$@" 2>/dev/null || sudo -n wg show "$@" 2>/dev/null
}

wg_latest_handshake_ok() {
  local iface=$1
  local rows now peer epoch age saw_peer=0

  if ! rows=$(wg_show_local "$iface" latest-handshakes 2>/dev/null); then
    if command -v sudo >/dev/null 2>&1 && ! sudo -n true 2>/dev/null; then
      warn "cannot read WireGuard handshakes for local interface $iface; run sudo -v before this script"
    else
      warn "cannot read WireGuard handshakes for local interface $iface"
    fi
    return 1
  fi

  if [[ -z "$rows" ]]; then
    warn "local $iface has no peers"
    return 1
  fi

  now=$(date +%s)
  while read -r peer epoch; do
    [[ -z "${peer:-}" ]] && continue
    saw_peer=1
    if [[ "$epoch" =~ ^[0-9]+$ && "$epoch" -gt 0 ]]; then
      age=$((now - epoch))
      if (( age <= HANDSHAKE_MAX_AGE )); then
        ok "local $iface handshake with $peer is fresh (${age}s old)"
        return 0
      fi
      warn "local $iface handshake with $peer is stale (${age}s old)"
    else
      warn "local $iface has no completed handshake with $peer"
    fi
  done <<< "$rows"

  if (( saw_peer == 0 )); then
    warn "local $iface has no peers"
  fi
  return 1
}

remote_wg_latest_handshakes() {
  remote_capture "wg show $(sq "$VPS_WG_IFACE") latest-handshakes 2>/dev/null || sudo -n wg show $(sq "$VPS_WG_IFACE") latest-handshakes 2>/dev/null"
}

check_remote_wg_handshake() {
  local rows now saw_peer=0 peer epoch age

  rows=$(remote_wg_latest_handshakes || true)
  if [[ -z "$rows" ]]; then
    warn "cannot read WireGuard handshakes for VPS interface $VPS_WG_IFACE"
    return 1
  fi

  now=$(date +%s)
  while read -r peer epoch; do
    [[ -z "${peer:-}" ]] && continue
    saw_peer=1
    if [[ "$epoch" =~ ^[0-9]+$ && "$epoch" -gt 0 ]]; then
      age=$((now - epoch))
      if (( age <= HANDSHAKE_MAX_AGE )); then
        ok "VPS $VPS_WG_IFACE handshake with $peer is fresh (${age}s old)"
        return 0
      fi
      warn "VPS $VPS_WG_IFACE handshake with $peer is stale (${age}s old)"
    else
      warn "VPS $VPS_WG_IFACE has no completed handshake with $peer"
    fi
  done <<< "$rows"

  if (( saw_peer == 0 )); then
    warn "VPS $VPS_WG_IFACE has no peers"
  fi
  return 1
}

heading "Inputs"
printf 'VPS_SSH=%s\n' "${VPS_SSH:-<unset>}"
printf 'HOME_WG_IFACE=%s\n' "$HOME_WG_IFACE"
printf 'VPS_WG_IFACE=%s\n' "$VPS_WG_IFACE"
printf 'HOME_WG_IP=%s\n' "$HOME_WG_IP"
printf 'VPS_WG_IP=%s\n' "$VPS_WG_IP"
printf 'XRAY_SOCKS=%s\n' "$XRAY_SOCKS"
printf 'ROUTE_MARK=%s\n' "${ROUTE_MARK:-<unset>}"
printf 'IP_CHECK_URL=%s\n' "$IP_CHECK_URL"

heading "Local prerequisites"
need curl || true
need ssh || true
need ping || true
if command -v wg >/dev/null 2>&1; then
  ok "wg is available locally"
else
  warn "wg is not in PATH locally; handshake checks may need wireguard-tools"
fi

heading "Public IP baseline"
home_ip=$(local_public_ip 2>/dev/null || true)
if [[ -n "$home_ip" ]]; then
  ok "local public IPv4: $home_ip"
else
  fail "cannot read local public IPv4 via $IP_CHECK_URL"
fi

expected_home_ip="${EXPECT_HOME_IP:-$home_ip}"
if [[ -z "$expected_home_ip" ]]; then
  fail "cannot establish expected home IP; set EXPECT_HOME_IP manually"
fi

vps_ip=""
if [[ -n "$VPS_SSH" ]]; then
  vps_ip=$(remote_capture "curl -4fsS --max-time $(sq "$TIMEOUT") $(sq "$IP_CHECK_URL") | tr -d '[:space:]'" || true)
  if [[ -n "$vps_ip" ]]; then
    ok "VPS normal public IPv4: $vps_ip"
    if [[ -n "$expected_home_ip" && "$vps_ip" == "$expected_home_ip" ]]; then
      warn "VPS normal curl already equals home IP; make sure the VPS default route is not globally routed home"
    fi
  else
    fail "cannot read VPS public IPv4 over SSH"
  fi
fi

heading "WireGuard layer"
wg_latest_handshake_ok "$HOME_WG_IFACE" || true

if ping -q -c "$PING_COUNT" -W "$PING_TIMEOUT" "$VPS_WG_IP" >/dev/null 2>&1; then
  ok "home can ping VPS tunnel IP $VPS_WG_IP"
else
  fail "home cannot ping VPS tunnel IP $VPS_WG_IP"
fi

if [[ -n "$VPS_SSH" ]]; then
  check_remote_wg_handshake || true
  if remote_capture "ping -q -c $(sq "$PING_COUNT") -W $(sq "$PING_TIMEOUT") $(sq "$HOME_WG_IP") >/dev/null" >/dev/null; then
    ok "VPS can ping home tunnel IP $HOME_WG_IP"
  else
    fail "VPS cannot ping home tunnel IP $HOME_WG_IP"
  fi
fi

if [[ -n "$VPS_SSH" && -n "$ROUTE_MARK" ]]; then
  heading "VPS policy routing"
  route_result=$(remote_sh "ip route get 1.1.1.1 mark $(sq "$ROUTE_MARK")" 2>/dev/null || true)
  if [[ -n "$route_result" ]]; then
    printf '%s\n' "$route_result"
    if [[ "$route_result" == *"$VPS_WG_IFACE"* ]]; then
      ok "marked traffic routes through $VPS_WG_IFACE"
    else
      fail "marked traffic does not route through $VPS_WG_IFACE"
    fi
  else
    fail "cannot evaluate marked route on VPS"
  fi
fi

heading "Xray through WG"
if [[ -n "$VPS_SSH" ]]; then
  xray_ip=$(remote_capture "curl -4fsS --max-time $(sq "$TIMEOUT") -x $(sq "socks5h://$XRAY_SOCKS") $(sq "$IP_CHECK_URL") | tr -d '[:space:]'" || true)
  if [[ -n "$xray_ip" ]]; then
    ok "VPS Xray SOCKS public IPv4: $xray_ip"
    if [[ -n "$expected_home_ip" && "$xray_ip" == "$expected_home_ip" ]]; then
      ok "Xray egress matches expected home IP"
    else
      fail "Xray egress does not match expected home IP (${expected_home_ip:-unknown})"
    fi
  else
    fail "cannot curl through VPS Xray SOCKS at $XRAY_SOCKS"
  fi
fi

heading "Summary"
printf 'warnings=%s failures=%s\n' "$warnings" "$failures"

if (( failures > 0 )); then
  exit 1
fi

exit 0
