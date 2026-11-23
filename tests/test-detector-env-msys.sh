#!/usr/bin/env bash
# 2026-11-23: Git Bash rewrote CMD_RAW="#/tmp/h --bg" into a Windows path for native python
# (#360). safety.sh still hands the detector CMD and CMD_CODE as env values. This checks,
# in the same shape as safety.sh's call, that python sees each value byte for byte.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

n=0
while IFS= read -r v; do
  n=$((n+1)); begin_test "env value $n"; got=$(CMD="$v" CMD_CODE="$v" python3 -c 'import os,sys; sys.stdout.write(os.environ["CMD"] + "\n" + os.environ["CMD_CODE"])')
  want="$v"$'\n'"$v"
  [ "$got" = "$want" ] && pass || fail "env value rewritten: [$v] -> [${got//$'\n'/ | }]"
done <<'VALUES'
h --bg
/tmp/h --bg
#/tmp/h --bg
cat /etc/passwd
chmod +x /tmp/a && /tmp/a
a=/tmp/b
--out=/tmp/b
/usr/bin/curl -o /tmp/x http://e.x
/tmp/a:/tmp/b
open("/etc/shadow").read()
VALUES
report
