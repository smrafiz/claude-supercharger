#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

HOOK="$REPO_DIR/hooks/subagent-stop-check.sh"

echo "=== Subagent Stop Check Tests ==="

begin_test "subagent-stop-check: flags 'couldn't' in last message"
INPUT='{"agent_name":"researcher","last_assistant_message":"I couldn'\''t find the file you requested.","cwd":"/tmp"}'
OUT=$(printf '%s' "$INPUT" | bash "$HOOK" 2>/dev/null)
echo "$OUT" | grep -q "systemMessage" && pass || fail "no systemMessage for inability"

begin_test "subagent-stop-check: flags failure in last message"
INPUT='{"agent_name":"builder","last_assistant_message":"The build failed to complete due to missing dependencies.","cwd":"/tmp"}'
OUT=$(printf '%s' "$INPUT" | bash "$HOOK" 2>/dev/null)
echo "$OUT" | grep -qi "failure\|failed" && pass || fail "failure not flagged"

begin_test "subagent-stop-check: flags TODO in last message"
INPUT='{"agent_name":"coder","last_assistant_message":"I have implemented the basic structure. TODO: add error handling.","cwd":"/tmp"}'
OUT=$(printf '%s' "$INPUT" | bash "$HOOK" 2>/dev/null)
echo "$OUT" | grep -q "systemMessage" && pass || fail "no systemMessage for TODO"

begin_test "subagent-stop-check: flags deferred work"
INPUT='{"agent_name":"analyst","last_assistant_message":"You would need to configure the database connection separately.","cwd":"/tmp"}'
OUT=$(printf '%s' "$INPUT" | bash "$HOOK" 2>/dev/null)
echo "$OUT" | grep -q "systemMessage" && pass || fail "no systemMessage for deferred work"

begin_test "subagent-stop-check: includes agent name in message"
INPUT='{"agent_name":"my-researcher","last_assistant_message":"I was unable to access the remote API.","cwd":"/tmp"}'
OUT=$(printf '%s' "$INPUT" | bash "$HOOK" 2>/dev/null)
echo "$OUT" | grep -qi "my-researcher" && pass || fail "agent name not in message"

begin_test "subagent-stop-check: no output for clean completion"
INPUT='{"agent_name":"coder","last_assistant_message":"I have successfully implemented the feature and all tests pass.","cwd":"/tmp"}'
OUT=$(printf '%s' "$INPUT" | bash "$HOOK" 2>/dev/null)
[ -z "$OUT" ] && pass || fail "should not flag clean completion"

begin_test "subagent-stop-check: no output when last_assistant_message missing"
INPUT='{"agent_name":"coder","cwd":"/tmp"}'
OUT=$(printf '%s' "$INPUT" | bash "$HOOK" 2>/dev/null)
[ -z "$OUT" ] && pass || fail "should produce no output when message missing"

begin_test "subagent-stop-check: no output for malformed input"
OUT=$(printf '{}' | bash "$HOOK" 2>/dev/null)
[ -z "$OUT" ] && pass || fail "should produce no output for empty input"

report
