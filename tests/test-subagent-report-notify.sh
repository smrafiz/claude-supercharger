#!/usr/bin/env bash
# Tests for v2.7.4 subagent-report-notify.sh — blocking SubagentStop hook that
# points the parent at the recovered report when the subagent's final message
# is a degraded stub (CC return-channel bug #54323).
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

H="$REPO_DIR/hooks/subagent-report-notify.sh"

echo "=== Subagent Report Notify Tests (v2.7.4) ==="

export SUPERCHARGER_NO_DEDUP=1

emit() { # stdin JSON -> 1 if it injected the report pointer, else 0
  grep -c "SUBAGENT REPORT" 2>/dev/null
}

for stub in "Ready." "Standing by." "[Agent stopped]" "Complete." "[No user message.]" "Done." "Acknowledged."; do
  begin_test "notify: degraded stub \"$stub\" points parent to report"
  n=$(echo "{\"agent_id\":\"a$RANDOM\",\"agent_name\":\"Marie\",\"last_assistant_message\":\"$stub\",\"session_id\":\"s$RANDOM\"}" | bash "$H" 2>/dev/null | emit)
  [ "$n" -ge 1 ] && pass || fail "expected report pointer for stub '$stub'"
done

begin_test "notify: empty final message is treated as degraded"
n=$(echo '{"agent_id":"aE","agent_name":"x","last_assistant_message":"","session_id":"sE"}' | bash "$H" 2>/dev/null | emit)
[ "$n" -ge 1 ] && pass || fail "expected pointer for empty final"

begin_test "notify: substantive final message stays silent"
n=$(echo '{"agent_id":"aF1","agent_name":"x","last_assistant_message":"Found 3 bugs in src/app.ts:42 with repro steps and a fix.","session_id":"sF1"}' | bash "$H" 2>/dev/null | emit)
[ "$n" -eq 0 ] && pass || fail "expected silence on full final"

begin_test "notify: short but substantive (has path) stays silent"
n=$(echo '{"agent_id":"aF2","agent_name":"x","last_assistant_message":"see src/x.ts:10","session_id":"sF2"}' | bash "$H" 2>/dev/null | emit)
[ "$n" -eq 0 ] && pass || fail "expected silence when final has a path reference"

begin_test "notify: missing agent_id exits silently (rc 0)"
echo '{"last_assistant_message":"Ready."}' | bash "$H" >/dev/null 2>&1
[ "$?" -eq 0 ] && pass || fail "expected rc 0 with no agent_id"

begin_test "notify: message names the read command and the report path"
out=$(echo '{"agent_id":"aCMD","agent_name":"Sherlock","last_assistant_message":"Ready.","session_id":"sCMD"}' | bash "$H" 2>/dev/null)
echo "$out" | grep -q "subagent-report.sh aCMD" && echo "$out" | grep -q "subagent-reports/aCMD.md" \
  && pass || fail "expected both the read command and the report path in the pointer"

begin_test "notify: emits additionalContext (not systemMessage)"
out=$(echo '{"agent_id":"aAC","agent_name":"x","last_assistant_message":"Ready.","session_id":"sAC"}' | bash "$H" 2>/dev/null)
echo "$out" | grep -q '"additionalContext"' && ! echo "$out" | grep -q '"systemMessage"' \
  && pass || fail "expected additionalContext channel"

# Dedup is a real feature — verify a second identical call is suppressed.
begin_test "notify: dedup suppresses a repeated pointer in the same session"
unset SUPERCHARGER_NO_DEDUP
rm -f "$HOME/.claude/supercharger/scope/.dedup-sDUP-subagent-report-notify"
J='{"agent_id":"aDUP","agent_name":"x","last_assistant_message":"Ready.","session_id":"sDUP"}'
first=$(echo "$J" | bash "$H" 2>/dev/null | emit)
second=$(echo "$J" | bash "$H" 2>/dev/null | emit)
rm -f "$HOME/.claude/supercharger/scope/.dedup-sDUP-subagent-report-notify"
export SUPERCHARGER_NO_DEDUP=1
[ "$first" -ge 1 ] && [ "$second" -eq 0 ] && pass || fail "expected first=emit second=suppressed (got $first/$second)"

# v2.19.1: when the recovered report is already on disk, INLINE its tail (the
# findings) into the pointer so the parent gets them without a recovery command.
begin_test "notify: inlines recovered findings when the report is on disk"
_NST=$(mktemp -d); mkdir -p "$_NST/scope/subagent-reports"
printf '## Block 1\nscratch\n\n## Block N\nUNIQUE_FINDINGS_MARKER: agent-router KILL, context-advisor OPTIMIZE\n' > "$_NST/scope/subagent-reports/inl1.md"
_OUT=$(echo '{"agent_id":"inl1","agent_name":"Critic","last_assistant_message":"Complete.","session_id":"zi1"}' \
  | SUPERCHARGER_STATE="$_NST" SUPERCHARGER_HOME="$REPO_DIR" bash "$H" 2>/dev/null)
_CTX=$(printf '%s' "$_OUT" | python3 -c 'import sys,json; print(json.load(sys.stdin)["hookSpecificOutput"]["additionalContext"])' 2>/dev/null || echo "")
echo "$_CTX" | grep -q 'UNIQUE_FINDINGS_MARKER' && pass || fail "findings not inlined: ${_CTX:0:80}"
rm -rf "$_NST"

begin_test "notify: falls back to a pointer when the report is not on disk yet"
_NST=$(mktemp -d); mkdir -p "$_NST/scope/subagent-reports"
_OUT=$(echo '{"agent_id":"inl2","agent_name":"x","last_assistant_message":"Done.","session_id":"zi2"}' \
  | SUPERCHARGER_STATE="$_NST" SUPERCHARGER_HOME="$REPO_DIR" bash "$H" 2>/dev/null)
{ echo "$_OUT" | grep -q 'SUBAGENT REPORT' && echo "$_OUT" | grep -q 'retry the command once'; } && pass \
  || fail "expected pointer+retry fallback when report absent"
rm -rf "$_NST"

begin_test "notify: inline respects the cap (large report → bounded, tail kept)"
_NST=$(mktemp -d); mkdir -p "$_NST/scope/subagent-reports"
python3 -c 'print("PAD "*400 + "TAILMARK_END")' > "$_NST/scope/subagent-reports/inl3.md"
_OUT=$(echo '{"agent_id":"inl3","last_assistant_message":"Complete.","session_id":"zi3"}' \
  | SUPERCHARGER_STATE="$_NST" SUPERCHARGER_HOME="$REPO_DIR" SUPERCHARGER_SUBAGENT_INLINE_CAP=300 bash "$H" 2>/dev/null)
_CTX=$(printf '%s' "$_OUT" | python3 -c 'import sys,json; print(json.load(sys.stdin)["hookSpecificOutput"]["additionalContext"])' 2>/dev/null || echo "")
{ echo "$_CTX" | grep -q 'TAILMARK_END' && [ "$(printf '%s' "$_CTX" | wc -c)" -lt 900 ]; } && pass \
  || fail "cap not respected or tail missed (len=$(printf '%s' "$_CTX" | wc -c))"
rm -rf "$_NST"

report
