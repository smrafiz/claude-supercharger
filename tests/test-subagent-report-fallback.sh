#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

HOOK="$REPO_DIR/hooks/subagent-report-fallback.sh"

echo "=== Subagent Report Fallback Tests (v2.7.1) ==="

export SUPERCHARGER_NO_DEDUP=1

_mk_transcript() {
  local path="$1"
  python3 -c "
import json, sys
out = open(sys.argv[1], 'w')
for block in sys.argv[2:]:
    rec = {'type':'assistant','message':{'role':'assistant','content':[{'type':'text','text':block}]}}
    out.write(json.dumps(rec) + '\n')
" "$path" "$@"
}

begin_test "fallback: skips when report file already exists"
setup_test_home
mkdir -p "$HOME/.claude/supercharger/scope/subagent-reports"
echo "existing content" > "$HOME/.claude/supercharger/scope/subagent-reports/agent1.md"
TMP=$(mktemp -d)
_mk_transcript "$TMP/agent1.output" "" "this is a long FINDING block that exceeds 80 characters definitely so it should normally be captured"
OUT=$(printf '%s' "{\"agent_id\":\"agent1\",\"agent_transcript_path\":\"$TMP/agent1.output\"}" | bash "$HOOK" 2>&1)
CONTENT=$(cat "$HOME/.claude/supercharger/scope/subagent-reports/agent1.md")
rm -rf "$TMP"
[ "$CONTENT" = "existing content" ] && pass || fail "overwrote existing report: $CONTENT"
teardown_test_home

begin_test "fallback: writes report when transcript has structured markers"
setup_test_home
mkdir -p "$HOME/.claude/supercharger/scope/subagent-reports"
TMP=$(mktemp -d)
_mk_transcript "$TMP/agent2.output" "" "Ready." "FINDING: identified 3 bugs in safety.sh"
OUT=$(printf '%s' "{\"agent_id\":\"agent2\",\"agent_transcript_path\":\"$TMP/agent2.output\"}" | bash "$HOOK" 2>&1)
rm -rf "$TMP"
grep -q "FINDING" "$HOME/.claude/supercharger/scope/subagent-reports/agent2.md" && pass || fail "no FINDING in recovered report"
teardown_test_home

begin_test "fallback: writes long blocks when no structured markers"
setup_test_home
mkdir -p "$HOME/.claude/supercharger/scope/subagent-reports"
TMP=$(mktemp -d)
_mk_transcript "$TMP/agent3.output" "" "Ready." "This is a substantial unstructured response that does not contain any of the structured markers but is long enough to be captured as a fallback"
OUT=$(printf '%s' "{\"agent_id\":\"agent3\",\"agent_transcript_path\":\"$TMP/agent3.output\"}" | bash "$HOOK" 2>&1)
rm -rf "$TMP"
grep -q "substantial unstructured" "$HOME/.claude/supercharger/scope/subagent-reports/agent3.md" && pass || fail "long-block fallback didn't fire"
teardown_test_home

begin_test "fallback: exits 0 with no agent_id"
setup_test_home
OUT=$(printf '%s' '{"session_id":"x"}' | bash "$HOOK" 2>&1)
EXIT=$?
teardown_test_home
[ "$EXIT" -eq 0 ] && pass || fail "exit=$EXIT"

begin_test "fallback: exits 0 with malformed JSON"
setup_test_home
OUT=$(printf '%s' 'not json' | bash "$HOOK" 2>&1)
EXIT=$?
teardown_test_home
[ "$EXIT" -eq 0 ] && pass || fail "exit=$EXIT"

begin_test "fallback: exits 0 when transcript not found"
setup_test_home
mkdir -p "$HOME/.claude/supercharger/scope/subagent-reports"
OUT=$(printf '%s' '{"agent_id":"nonexistent-xyz","agent_transcript_path":"/tmp/does-not-exist.output"}' | bash "$HOOK" 2>&1)
EXIT=$?
teardown_test_home
[ "$EXIT" -eq 0 ] && pass || fail "exit=$EXIT"

begin_test "fallback: empty transcript produces no report"
setup_test_home
mkdir -p "$HOME/.claude/supercharger/scope/subagent-reports"
TMP=$(mktemp -d)
: > "$TMP/agent4.output"
OUT=$(printf '%s' "{\"agent_id\":\"agent4\",\"agent_transcript_path\":\"$TMP/agent4.output\"}" | bash "$HOOK" 2>&1)
EXISTS=$([ -f "$HOME/.claude/supercharger/scope/subagent-reports/agent4.md" ] && echo "yes" || echo "no")
rm -rf "$TMP"
[ "$EXISTS" = "no" ] && pass || fail "empty transcript produced empty report"
teardown_test_home

report
