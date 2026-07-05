#!/usr/bin/env bash
set -euo pipefail

VPS_SSH="${VPS_SSH:-root@66.245.220.84}"
SSH_OPTS="${SSH_OPTS:--F /dev/null -i ./vultr_vps_relay_china -o IdentitiesOnly=yes}"
SECONDS_TO_WATCH="${SECONDS_TO_WATCH:-90}"
WATCH_FILTER="${WATCH_FILTER:-vless-reality|REALITY|accepted|handshake|email: physshell}"

declare -a ssh_opts=()
# shellcheck disable=SC2206
ssh_opts=( $SSH_OPTS )

ssh "${ssh_opts[@]}" "$VPS_SSH" \
  "timeout '$SECONDS_TO_WATCH' journalctl -u xray -f --no-pager | grep --line-buffered -E '$WATCH_FILTER' || true"
