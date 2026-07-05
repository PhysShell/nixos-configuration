#!/usr/bin/env bash
set -u
set -o pipefail

DEFAULT_TARGET="${DEFAULT_TARGET:-66.245.220.84}"
TARGETS_INPUT="${TARGETS:-${VPS_TARGETS:-}}"
LOCAL_LABEL="${LOCAL_LABEL:-Almaty / Beeline / current connection}"
CHINA_SOURCES="${CHINA_SOURCES-China,China Telecom,China Unicom,China Mobile}"
GLOBALPING_LIMIT="${GLOBALPING_LIMIT:-3}"
LOCAL_PING_COUNT="${LOCAL_PING_COUNT:-8}"
LOCAL_PING_TIMEOUT="${LOCAL_PING_TIMEOUT:-3}"
TCP_PORTS="${TCP_PORTS:-443 22}"
TCP_TIMEOUT="${TCP_TIMEOUT:-5}"
RUN_MTR="${RUN_MTR:-0}"
MTR_COUNT="${MTR_COUNT:-10}"
MTR_LIMIT="${MTR_LIMIT:-1}"
IP_CHECK_URL="${IP_CHECK_URL:-https://ifconfig.co}"
IP_VERSION="${IP_VERSION:-4}"
HOME_TARGET="${HOME_TARGET:-}"
VPS_SSH="${VPS_SSH:-}"
SSH_OPTS="${SSH_OPTS:-}"

failures=0
warnings=0

heading() {
  printf '\n== %s ==\n' "$1"
}

warn() {
  warnings=$((warnings + 1))
  printf 'warn: %s\n' "$1" >&2
}

fail() {
  failures=$((failures + 1))
  printf 'fail: %s\n' "$1" >&2
}

trim() {
  local value=$1
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

split_targets() {
  local input=$1
  input=${input//,/ }
  # shellcheck disable=SC2206
  local items=( $input )
  printf '%s\n' "${items[@]}"
}

split_csv() {
  local input=$1
  local item
  while IFS= read -r item; do
    item=$(trim "$item")
    [[ -n "$item" ]] && printf '%s\n' "$item"
  done < <(printf '%s\n' "$input" | tr ',' '\n')
}

need() {
  if ! command -v "$1" >/dev/null 2>&1; then
    fail "missing command: $1"
    return 1
  fi
}

sq() {
  local value=${1//\'/\'\\\'\'}
  printf "'%s'" "$value"
}

declare -a ssh_opts=()
if [[ -n "$SSH_OPTS" ]]; then
  # shellcheck disable=SC2206
  ssh_opts=( $SSH_OPTS )
fi

remote_sh() {
  local command=$1

  if [[ -z "$VPS_SSH" ]]; then
    return 1
  fi

  # shellcheck disable=SC2029
  ssh "${ssh_opts[@]}" "$VPS_SSH" "bash -o pipefail -c $(sq "$command")"
}

local_public_ip() {
  curl -4fsS --max-time 8 "$IP_CHECK_URL" | tr -d '[:space:]'
}

is_ipv4_literal() {
  [[ "$1" =~ ^[0-9]+(\.[0-9]+){3}$ ]]
}

is_ipv6_literal() {
  [[ "$1" == *:* ]]
}

target_versions() {
  local target=$1

  if is_ipv4_literal "$target"; then
    printf '4\n'
    return
  fi

  if is_ipv6_literal "$target"; then
    printf '6\n'
    return
  fi

  case "$IP_VERSION" in
    4|6)
      printf '%s\n' "$IP_VERSION"
      ;;
    both)
      printf '4\n6\n'
      ;;
    *)
      fail "invalid IP_VERSION=$IP_VERSION; expected 4, 6, or both"
      return 1
      ;;
  esac
}

globalping_ping() {
  local target=$1
  local source=$2
  local version=$3
  local -a ip_flags=()

  if ! is_ipv4_literal "$target" && ! is_ipv6_literal "$target"; then
    ip_flags=(--ipv"$version")
  fi

  printf '\n-- China IPv%s probe: %s -> %s --\n' "$version" "$source" "$target"
  globalping ping "$target" --from "$source" --limit "$GLOBALPING_LIMIT" --latency --ci "${ip_flags[@]}"
}

globalping_mtr() {
  local target=$1
  local source=$2
  local version=$3
  local -a ip_flags=()

  if ! is_ipv4_literal "$target" && ! is_ipv6_literal "$target"; then
    ip_flags=(--ipv"$version")
  fi

  printf '\n-- China IPv%s MTR: %s -> %s --\n' "$version" "$source" "$target"
  globalping mtr "$target" --from "$source" --limit "$MTR_LIMIT" --ci "${ip_flags[@]}"
}

local_ping() {
  local target=$1
  local version=$2

  printf '\n-- Local IPv%s ping: %s -> %s --\n' "$version" "$LOCAL_LABEL" "$target"
  ping "-$version" -c "$LOCAL_PING_COUNT" -W "$LOCAL_PING_TIMEOUT" "$target"
}

tcp_probe() {
  local target=$1
  local port=$2
  local version=$3

  printf '\n-- Local IPv%s TCP: %s:%s --\n' "$version" "$target" "$port"
  nc "-$version" -vz -w "$TCP_TIMEOUT" "$target" "$port"
}

local_mtr() {
  local target=$1
  local version=$2

  printf '\n-- Local IPv%s MTR: %s -> %s --\n' "$version" "$LOCAL_LABEL" "$target"
  mtr "-$version" -r -c "$MTR_COUNT" "$target"
}

usage() {
  cat <<'USAGE'
Usage:
  nix run .#route-probe -- 66.245.220.84
  nix develop -c route-probe 66.245.220.84

Inputs:
  positional args / TARGETS   VPS IPs or hostnames to test.

Useful variables:
  CHINA_SOURCES       Comma-separated Globalping sources.
                      Default: China,China Telecom,China Unicom,China Mobile
                      Set CHINA_SOURCES="" to skip China-side probes.
  GLOBALPING_LIMIT    Probes per source, default: 3
  LOCAL_LABEL         Label for local tests, default: Almaty / Beeline / current connection
  IP_VERSION          4, 6, or both. Default: 4
  TCP_PORTS           Local TCP ports to test, default: 443 22
  RUN_MTR=1           Also run local and China MTR tests
  VPS_SSH             Optional current VPS SSH target for VPS -> home ping
  SSH_OPTS            Extra ssh options for VPS_SSH
  HOME_TARGET         Optional home public IP/host for VPS -> home ping.
                      Defaults to local public IPv4 from https://ifconfig.co when possible.

What to compare:
  China -> VPS        Globalping ping/MTR from Chinese probes
  Almaty -> VPS       Local Beeline ping/TCP/MTR from this machine
  VPS -> Almaty       Optional SSH ping from current VPS back to HOME_TARGET
USAGE
}

case "${1:-}" in
  -h|--help)
    usage
    exit 0
    ;;
esac

declare -a targets=()
if (($# > 0)); then
  targets=( "$@" )
elif [[ -n "$TARGETS_INPUT" ]]; then
  while IFS= read -r target; do
    targets+=( "$target" )
  done < <(split_targets "$TARGETS_INPUT")
else
  targets=( "$DEFAULT_TARGET" )
fi

declare -a sources=()
while IFS= read -r source; do
  sources+=( "$source" )
done < <(split_csv "$CHINA_SOURCES")

heading "Inputs"
printf 'targets=%s\n' "${targets[*]}"
printf 'local=%s\n' "$LOCAL_LABEL"
printf 'china_sources=%s\n' "$CHINA_SOURCES"
printf 'ip_version=%s\n' "$IP_VERSION"
printf 'globalping_limit=%s\n' "$GLOBALPING_LIMIT"
printf 'run_mtr=%s\n' "$RUN_MTR"
printf 'vps_ssh=%s\n' "${VPS_SSH:-<unset>}"

heading "Prerequisites"
need curl || true
need ping || true
need nc || true
need globalping || true
if [[ "$RUN_MTR" == "1" ]]; then
  need mtr || true
fi

if (( failures > 0 )); then
  heading "Summary"
  printf 'warnings=%s failures=%s\n' "$warnings" "$failures"
  exit 1
fi

if [[ -z "$HOME_TARGET" ]]; then
  HOME_TARGET=$(local_public_ip 2>/dev/null || true)
fi

if [[ -n "$HOME_TARGET" ]]; then
  printf 'home_target=%s\n' "$HOME_TARGET"
else
  warn "cannot detect home public IPv4; set HOME_TARGET if you want VPS -> home checks"
fi

for target in "${targets[@]}"; do
  declare -a versions=()
  while IFS= read -r version; do
    versions+=( "$version" )
  done < <(target_versions "$target")

  for version in "${versions[@]}"; do
    heading "China -> VPS IPv$version: $target"
    for source in "${sources[@]}"; do
      if ! globalping_ping "$target" "$source" "$version"; then
        warn "Globalping IPv$version ping failed for source '$source' and target '$target'"
      fi

      if [[ "$RUN_MTR" == "1" ]]; then
        if ! globalping_mtr "$target" "$source" "$version"; then
          warn "Globalping IPv$version MTR failed for source '$source' and target '$target'"
        fi
      fi
    done

    heading "Almaty/Beeline -> VPS IPv$version: $target"
    if ! local_ping "$target" "$version"; then
      warn "local IPv$version ping failed for $target"
    fi

    for port in $TCP_PORTS; do
      if ! tcp_probe "$target" "$port" "$version"; then
        warn "local IPv$version TCP probe failed for $target:$port"
      fi
    done

    if [[ "$RUN_MTR" == "1" ]]; then
      if ! local_mtr "$target" "$version"; then
        warn "local IPv$version MTR failed for $target"
      fi
    fi
  done
done

if [[ -n "$VPS_SSH" && -n "$HOME_TARGET" ]]; then
  heading "Current VPS -> Home: $HOME_TARGET"
  if ! remote_sh "ping -4 -c $(sq "$LOCAL_PING_COUNT") -W $(sq "$LOCAL_PING_TIMEOUT") $(sq "$HOME_TARGET")"; then
    warn "VPS -> home ping failed"
  fi
fi

heading "Summary"
printf 'warnings=%s failures=%s\n' "$warnings" "$failures"

if (( failures > 0 )); then
  exit 1
fi
