#!/usr/bin/env bash
# 2026-11-23: Git Bash rewrites env values for native Windows python when the value starts
# with "/" or has no spaces: CMD_CODE='open("/etc/x")' arrived as open("C:/Program Files/
# Git/etc/x"), "/usr/bin/curl ... http://e.x" as "C:\...\curl ... http;\e.x" (CI run
# 45159143262). safety.sh therefore sends the detector `raw NUL cmd NUL code` on stdin.
# Each row: the detector must take CMD/CMD_CODE from stdin, byte for byte, even when the
# env holds something else.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

# The detector's own startup lines, run with a print instead of the checks after them.
START=$(sed -n '/^cmd = os.environ.get("CMD", "")$/,/os.environ\["CMD_CODE"\] = _parts\[2\]/p' "$REPO_DIR/hooks/safety-detect.py")
n=0
while IFS= read -r v; do
  n=$((n+1)); begin_test "stdin channel row $n"
  got=$(printf '%s\0%s\0%s' "raw" "$v" "$v" | CMD=stale CMD_CODE=stale CMD_RAW_STDIN=1 python3 -c "import os, sys
$START
sys.stdout.buffer.write((cmd + '|' + os.environ['CMD'] + '|' + os.environ['CMD_CODE'] + '|' + cmd_raw).encode())")
  [ "$got" = "$v|$v|$v|raw" ] && pass || fail "[$v] -> [$got]"
done <<'VALUES'
h --bg
/tmp/h --bg
#/tmp/h --bg
a=/tmp/b
--out=/tmp/b
/usr/bin/curl -o /tmp/x http://e.x
/tmp/a:/tmp/b
open("/etc/shadow").read()
VALUES

begin_test "safety.sh sends cmd and code on stdin, not env"
L=$(grep -n 'safety-detect.py' "$REPO_DIR/hooks/safety.sh" | grep 'PY_REASON=' )
case "$L" in *"printf '%s\0%s\0%s'"*) case "$L" in *' CMD='*|*'CMD_CODE='*) fail "env still set: $L" ;; *) pass ;; esac ;; *) fail "no NUL-joined stdin: $L" ;; esac
report
