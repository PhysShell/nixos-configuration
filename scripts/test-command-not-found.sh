#!/usr/bin/env bash
# Regression test for hosts/wsl/command-not-found.nix on the running system.
#
# Answers go through a real pty (script(1)) for zsh and bash with the user's
# rc files, through a pipe (no terminal), and straight into the patched
# script.  Each case checks the exit code, how many times the prompt was
# printed, and whether the package actually ran.  A case killed at LIMIT
# seconds is the old EOF busy loop.
#
#   scripts/test-command-not-found.sh
#   CNF=/nix/store/...-command-not-found/bin/command-not-found SHELLS= \
#     scripts/test-command-not-found.sh     # negative control: unpatched copy
set -u
set -o pipefail

LIMIT="${LIMIT:-30}"
SHELLS="${SHELLS-zsh bash}"
CNF="${CNF:-/run/current-system/sw/bin/command-not-found}"
# A fresh login, so /etc/set-environment (NIX_AUTO_RUN*) is read again.
FRESH=(env -i HOME="$HOME" USER="$USER" LOGNAME="$USER" TERM=xterm-256color
  PATH=/run/current-system/sw/bin)
# figlet: one candidate, cowsay: two (cowsay, neo-cowsay).
ONE='figlet -f term RAN-MARK'
TWO='cowsay RAN-MARK'

failures=0
out=$(mktemp)
fifo=$(mktemp -u)
trap 'rm -f "$out" "$fifo"' EXIT

check() {
  local name=$1 want_rc=$2 want_prompts=$3 want_ran=$4 secs=$5
  local prompts ran=no
  prompts=$(grep -o 'confirm? \[yn\]\|Your choice' "$out" | wc -l)
  grep -q 'RAN-MARK' "$out" && ran=yes
  if [[ $rc == "$want_rc" && $prompts == "$want_prompts" && $ran == "$want_ran" ]]; then
    printf 'PASS  %-46s rc=%s prompts=%s ran=%s %ss\n' "$name" "$rc" "$prompts" "$ran" "$secs"
  else
    printf 'FAIL  %-46s rc=%s prompts=%s ran=%s %ss  (want rc=%s prompts=%s ran=%s)\n' \
      "$name" "$rc" "$prompts" "$ran" "$secs" "$want_rc" "$want_prompts" "$want_ran"
    tr -d '\r' <"$out" | head -c 600 | sed 's/^/      | /'
    failures=$((failures + 1))
  fi
}

# Typed input on a real terminal.  The fifo is held open, so the only EOF the
# handler can see is a typed Ctrl-D (\004), never script(1)'s stdin closing.
pty_case() {
  local name=$1 input=$2 sh=$3 cmd=$4; shift 4
  local t0=$SECONDS fd
  mkfifo "$fifo"
  exec {fd}<>"$fifo"
  printf '%b' "$input" >&"$fd"
  timeout -s KILL "$LIMIT" script -qec "${FRESH[*]} $sh -lic '$cmd'" /dev/null <"$fifo" >"$out" 2>&1
  rc=$?
  exec {fd}>&-
  rm -f "$fifo"
  check "$name" "$@" $((SECONDS - t0))
}

# stdin is a pipe: the shell handler must not prompt at all.
pipe_case() {
  local name=$1 input=$2 sh=$3 cmd=$4; shift 4
  local t0=$SECONDS
  printf '%b' "$input" | setsid -w timeout -s KILL "$LIMIT" "${FRESH[@]}" "$sh" -lic "$cmd" >"$out" 2>&1
  rc=${PIPESTATUS[1]}
  check "$name" "$@" $((SECONDS - t0))
}

# The script itself with auto-run forced on and a pipe for stdin: the EOF
# handling of the patch, without the shell's terminal check in front of it.
direct_case() {
  local name=$1 input=$2 cmd=$3; shift 3
  local t0=$SECONDS
  # shellcheck disable=SC2086 # $cmd is "program args"
  printf '%b' "$input" | NIX_AUTO_RUN=1 NIX_AUTO_RUN_INTERACTIVE=1 \
    setsid -w timeout -s KILL "$LIMIT" "$CNF" $cmd >"$out" 2>&1
  rc=${PIPESTATUS[1]}
  check "$name" "$@" $((SECONDS - t0))
}

profiles() {
  readlink -f ~/.nix-profile /etc/profiles/per-user/"$USER" /run/current-system/sw
  nix-env -q
  nix profile list 2>/dev/null | grep -c Name
}
before=$(profiles 2>&1)

echo "script under test: $(readlink -f "$CNF")"

#            name                                input            cmd     rc  prompts ran
direct_case 'direct: one, y'                     'y\n'            "$ONE"  0   1  yes
direct_case 'direct: one, EOF'                   ''               "$ONE"  127 1  no
direct_case 'direct: one, bad input, EOF'        'x\n'            "$ONE"  127 2  no
direct_case 'direct: two, 1'                     '1\n'            "$TWO"  0   1  yes
direct_case 'direct: two, EOF'                   ''               "$TWO"  127 1  no
direct_case 'direct: two, bad input x2, EOF'     '0\n3\n'         "$TWO"  127 3  no

for sh in $SHELLS; do
  pty_case  "$sh pty: one, y"                    'y\n'            "$sh" "$ONE"  0   1  yes
  pty_case  "$sh pty: one, n"                    'n\n'            "$sh" "$ONE"  0   1  no
  pty_case  "$sh pty: one, bad input, n"         'x\nn\n'         "$sh" "$ONE"  0   2  no
  pty_case  "$sh pty: one, Ctrl-D"               '\004'           "$sh" "$ONE"  127 1  no
  pty_case  "$sh pty: one, bad input, Ctrl-D"    'x\n\004'        "$sh" "$ONE"  127 2  no
  pty_case  "$sh pty: two, 1"                    '1\n'            "$sh" "$TWO"  0   1  yes
  pty_case  "$sh pty: two, Ctrl-D"               '\004'           "$sh" "$TWO"  127 1  no
  pty_case  "$sh pty: two, bad input x2, Ctrl-D" '9\nabc\n\004'   "$sh" "$TWO"  127 3  no
  pipe_case "$sh pipe: one, y (no prompt)"       'y\n'            "$sh" "$ONE"  127 0  no
  pipe_case "$sh pipe: two, EOF (no prompt)"     ''               "$sh" "$TWO"  127 0  no
done

after=$(profiles 2>&1)
if [[ $before == "$after" ]]; then
  echo "PASS  profiles unchanged (user, per-user, system, nix-env, nix profile)"
else
  echo "FAIL  profiles changed:"
  diff <(echo "$before") <(echo "$after")
  failures=$((failures + 1))
fi

echo "failures: $failures"
[[ $failures -eq 0 ]]
