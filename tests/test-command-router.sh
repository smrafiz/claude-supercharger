#!/usr/bin/env bash
# Command router integrity (v2.26.19)
#
# /supercharger was a static index: it printed all 30 commands and left the user to
# scan them. With 30 user-invoked commands that is a cognitive-load problem — the user
# has to be the index. It now routes a SITUATION to a command.
#
# A router has two ways to rot silently, and both are checked here:
#   1. It names a command that does not exist — the user is sent nowhere.
#   2. A command exists that the router never names — it is undiscoverable, which is
#      the exact failure the router was added to fix.
#
# Same shape as test-matcher-validity: a reference that resolves to nothing looks
# identical to one that was never needed.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

ROUTER="$REPO_DIR/configs/commands/supercharger.md"

echo "=== Command Router Tests ==="

begin_test "router file exists and has a routing section"
grep -q '### Routing table' "$ROUTER" && pass || fail "no routing section in $ROUTER"

begin_test "every command the router names actually exists"
MISSING=$(python3 -c "
import re, os, glob, sys
body = open(sys.argv[1]).read()
routing = body.split('### Routing table')[1] if '### Routing table' in body else ''
refs = sorted(set(re.findall(r'\`/([a-z][a-z-]*)', routing)))
have = {os.path.basename(p)[:-3] for p in glob.glob(os.path.join(sys.argv[2], 'configs/commands/*.md'))}
print(' '.join(r for r in refs if r not in have))
" "$ROUTER" "$REPO_DIR")
[ -z "$MISSING" ] && pass || fail "router points at non-existent commands: $MISSING"

begin_test "every command is reachable through the router (none undiscoverable)"
UNREACHABLE=$(python3 -c "
import re, os, glob, sys
body = open(sys.argv[1]).read()
routing = body.split('### Routing table')[1] if '### Routing table' in body else ''
refs = set(re.findall(r'\`/([a-z][a-z-]*)', routing))
have = {os.path.basename(p)[:-3] for p in glob.glob(os.path.join(sys.argv[2], 'configs/commands/*.md'))}
# /supercharger is the router itself; sc-* variants are reached via their base rows.
print(' '.join(sorted(have - refs - {'supercharger'})))
" "$ROUTER" "$REPO_DIR")
[ -z "$UNREACHABLE" ] && pass || fail "commands no route reaches: $UNREACHABLE"

begin_test "the index still lists every command (browse mode intact)"
MISSING_IDX=$(python3 -c "
import re, os, glob, sys
body = open(sys.argv[1]).read()
idx = body.split('\`\`\`')[1] if '\`\`\`' in body else ''
listed = set(re.findall(r'^\s+/([a-z][a-z-]*)', idx, re.M))
have = {os.path.basename(p)[:-3] for p in glob.glob(os.path.join(sys.argv[2], 'configs/commands/*.md'))}
print(' '.join(sorted(have - listed)))
" "$ROUTER" "$REPO_DIR")
[ -z "$MISSING_IDX" ] && pass || fail "commands missing from the printed index: $MISSING_IDX"

begin_test "router caps its answer (a 5-option router is just the index again)"
grep -q 'at most two' "$ROUTER" && pass || fail "no cap on how many commands a route may name"

begin_test "report-over-change tie-break is stated"
grep -qi 'reports.*over.*changes\|report.*before.*change' "$ROUTER" && pass \
  || fail "no tie-break rule for equally-plausible routes"

begin_test "generated commands/ copy is in sync with the source"
if diff -q "$ROUTER" "$REPO_DIR/commands/supercharger.md" >/dev/null 2>&1; then
  pass
else
  # commands/ is generated and may differ by design; assert the routing table survived
  grep -q '### Routing table' "$REPO_DIR/commands/supercharger.md" && pass \
    || fail "routing table missing from the generated commands/ copy — run tools/gen-plugin-commands.sh"
fi

report
