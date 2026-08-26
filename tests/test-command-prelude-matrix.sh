#!/usr/bin/env bash
# Generated coverage for the command PRELUDE — everything that can sit between the
# start of a command string and the verb a guard is looking for (v2.29.35).
#
# Why this file is generated rather than hand-written: three defects shipped on
# 2026-08-26 because the checks written alongside each fix did not vary a dimension.
#
#   v2.29.31  a GIT_SSH_COMMAND probe covered three legitimate ssh values, none
#             with a SPACE in the path — the shape the platform actually produces.
#   v2.29.32  a wrapper probe covered wrappers but no SEPARATORS, so a fix that
#             held only for `nohup rm -rf /` shipped claiming `true; nohup ...` too.
#   v2.29.34  structural logic was copied into a second pass that omitted two rules,
#             so a wrapper OUTSIDE a group still hid the verb.
#
# Each was found later by a matrix that varied the missing dimension. Hand-written
# cases encode the combinations someone thought of; this encodes all of them, so a
# new wrapper or structure is covered by adding one word to a list below.
#
# Payloads live in this file rather than on a command line so the installed guard
# does not block the runner itself.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck source=tests/helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

SAFETY="$REPO_DIR/hooks/safety.sh"
GITSAFETY="$REPO_DIR/hooks/git-safety.sh"
RM="r""m"

echo "=== Command prelude matrix (structure x wrapper x separator) ==="

# verdict <hook> <command> -> BLOCK | allow
verdict() {
  local j
  j=$(CMD="$2" python3 -c '
import json, os
print(json.dumps({"tool_name": "Bash", "cwd": "/tmp",
                  "tool_input": {"command": os.environ["CMD"]}}))')
  printf '%s' "$j" | bash "$1" >/dev/null 2>&1 && echo allow || echo BLOCK
}

# --- the three dimensions -----------------------------------------------------
# Adding an entry here extends coverage across every other dimension at once.
STRUCTURES=(
  '%s'                          # bare
  '( %s )'                      # subshell
  '{ %s; }'                     # brace group
  'if true; then %s; fi'        # conditional body
  'for i in 1; do %s; done'     # loop body
  'while false; do %s; done'    # while body
  'case x in x) %s;; esac'      # case arm
  'f() { %s; }; f'              # function body
  '( ( %s ) )'                  # nested grouping
)
WRAPPERS=('%s' 'nohup %s' 'setsid %s' 'timeout 5 %s' 'nice -n 10 %s'
          'sudo %s' 'sudo -u root %s' 'env %s' 'env -i %s' 'stdbuf -o0 %s')
SEPARATORS=('%s' 'true; %s' 'true && %s' 'false || %s' 'true & %s')

# --- destructive payloads must survive every combination ----------------------
_n=0
for _st in "${STRUCTURES[@]}"; do
  for _w in "${WRAPPERS[@]}"; do
    for _sep in "${SEPARATORS[@]}"; do
      # shellcheck disable=SC2059
      _inner=$(printf "$_st" "$RM -rf /")
      # shellcheck disable=SC2059
      _wrapped=$(printf "$_w" "$_inner")
      # shellcheck disable=SC2059
      _full=$(printf "$_sep" "$_wrapped")
      _n=$((_n + 1))
      begin_test "prelude #$_n blocks: ${_full:0:56}"
      [ "$(verdict "$SAFETY" "$_full")" = BLOCK ] && pass \
        || fail "prelude bypass: $_full"
    done
  done
done

# The git guard runs the same splitter, so it gets the same treatment on a smaller
# grid — enough to catch a splitter regression without doubling the runtime.
for _st in "${STRUCTURES[@]}"; do
  for _w in '%s' 'nohup %s' 'sudo -u root %s'; do
    # shellcheck disable=SC2059
    _inner=$(printf "$_st" "git push --force origin main")
    # shellcheck disable=SC2059
    _full=$(printf "$_w" "$_inner")
    begin_test "prelude (git) blocks: ${_full:0:56}"
    [ "$(verdict "$GITSAFETY" "$_full")" = BLOCK ] && pass \
      || fail "git prelude bypass: $_full"
  done
done

# --- and none of it may fire on ordinary shell --------------------------------
# Structure and wrappers are how shell is WRITTEN. A guard that fires here is one
# people learn to click through, which costs exactly the signal it exists to give.
BENIGN=(
  'for f in *.log; do gzip $f; done'
  'if [ -f .env ]; then echo present; fi'
  'while read -r l; do echo $l; done < list.txt'
  'case $1 in start) npm start;; stop) npm stop;; esac'
  '( cd build && make )'
  '{ echo one; echo two; }'
  'deploy() { npm ci && npm run build; }; deploy'
  'time npm test'
  'until nc -z localhost 5432; do sleep 1; done'
  'for d in */; do ( cd $d && npm ci ); done'
  'nohup npm run dev'
  'timeout 300 npm test'
  'sudo -u builder make install'
  'nice -n 19 make -j4'
  'git status && git log --oneline -5'
  'f() { git status; }; f'
)
for _b in "${BENIGN[@]}"; do
  begin_test "prelude allows ordinary shell: ${_b:0:52}"
  if [ "$(verdict "$SAFETY" "$_b")" = allow ] \
     && [ "$(verdict "$GITSAFETY" "$_b")" = allow ]; then
    pass
  else
    fail "over-blocked ordinary shell: $_b"
  fi
done

report
