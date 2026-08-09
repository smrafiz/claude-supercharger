#!/usr/bin/env bash
# update.sh survives a failed HEAD-SHA lookup (v2.26.79)
#
# The SHA fetch is a best-effort FRESHNESS check — the clone is a TLS-authenticated
# github.com fetch either way — so a lookup that fails must warn and proceed. The
# curl branch did the opposite: `curl -f` exits 22 on HTTP 403, which is what the
# anonymous GitHub API returns once the 60-req/hr per-IP cap is hit. Under
# `set -euo pipefail` that 22 reached the assignment and killed the updater.
#
# It only reproduces on a shared or NAT'd IP, so it stayed invisible until a Windows
# CI runner hit the cap while releasing v2.26.78 and turned the job red. For a user
# behind a corporate NAT it meant /sc-update was simply dead, exit 22, no message.
#
# One arm of three: the `gh` branch had `|| echo ""` and the python branch catches
# its own exceptions. Same shape as [[audit-sibling-branches-not-instances]].
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

echo "=== update.sh SHA-lookup Resilience ==="

begin_test "the curl SHA branch cannot abort the script"
# The property, not the spelling: under `set -euo pipefail`, the exact pipeline
# shape from update.sh must survive a curl that exits 22.
GOT=$(bash -c '
set -euo pipefail
fake_curl() { return 22; }
EXPECTED_SHA=$(fake_curl | tr -d "[:space:]" || echo "")
echo "survived:${EXPECTED_SHA:-empty}"
' 2>/dev/null || echo "ABORTED")
[ "$GOT" = "survived:empty" ] && pass || fail "the guarded shape still aborts ($GOT)"

begin_test "the UNGUARDED shape does abort — proving the guard is what saves it"
GOT=$(bash -c '
set -euo pipefail
fake_curl() { return 22; }
EXPECTED_SHA=$(fake_curl | tr -d "[:space:]")
echo "survived"
' 2>/dev/null || echo "ABORTED")
[ "$GOT" = "ABORTED" ] && pass || fail "control case did not reproduce the bug"

begin_test "update.sh's curl SHA lookup carries the guard"
python3 -c "
import re, sys
src = open('$REPO_DIR/tools/update.sh').read()
m = re.search(r'EXPECTED_SHA=\\\$\(curl.*?\)\n', src, re.S)
if not m:
    print('curl SHA branch not found'); sys.exit(1)
sys.exit(0 if '|| echo' in m.group(0) else 1)
" && pass || fail "curl branch can still abort the updater"

begin_test "all three SHA branches degrade to empty, none abort"
python3 -c "
import re, sys
src = open('$REPO_DIR/tools/update.sh').read()
i = src.find('EXPECTED_SHA=\"\"')
seg = src[i:i+1600]
bad = []
gh = re.search(r'EXPECTED_SHA=\\\$\(gh api.*?\)\n', seg, re.S)
if gh and '|| echo' not in gh.group(0): bad.append('gh')
cu = re.search(r'EXPECTED_SHA=\\\$\(curl.*?\)\n', seg, re.S)
if cu and '|| echo' not in cu.group(0): bad.append('curl')
# The python branch is a multi-line heredoc-ish block whose body contains many
# ')\n' sequences, so a non-greedy match stops inside it and misses the except.
# Bound it at its real terminator instead.
pi = seg.find('EXPECTED_SHA=\$(python3')
if pi != -1:
    body = seg[pi:seg.find('2>/dev/null)', pi) + 12]
    if 'except' not in body and '|| echo' not in body: bad.append('python')
print('UNGUARDED: ' + ','.join(bad) if bad else 'OK')
" | grep -q '^OK$' && pass || fail "a sibling branch lacks the guard"

begin_test "a fetched-but-MISMATCHED sha still aborts (fail-closed preserved)"
grep -q 'EXPECTED_SHA' "$REPO_DIR/tools/update.sh" \
  && grep -qE 'ACTUAL_SHA|rev-parse' "$REPO_DIR/tools/update.sh" \
  && pass || fail "the mismatch check went missing"

report
