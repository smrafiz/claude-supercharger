#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

HOOK="$REPO_DIR/hooks/permission-denied-advisor.sh"

echo "=== Permission Denied Advisor Tests ==="

begin_test "permission-denied-advisor: emits systemMessage on denial"
INPUT='{"tool_name":"Bash","tool_input":{"command":"rm -rf /tmp/test"},"cwd":"/tmp"}'
OUT=$(printf '%s' "$INPUT" | bash "$HOOK" 2>/dev/null)
echo "$OUT" | grep -q "systemMessage" && pass || fail "no systemMessage for denied permission"

begin_test "permission-denied-advisor: includes tool name in message"
INPUT='{"tool_name":"Write","tool_input":{"file_path":"/etc/hosts"},"cwd":"/tmp"}'
OUT=$(printf '%s' "$INPUT" | bash "$HOOK" 2>/dev/null)
echo "$OUT" | grep -qi "Write" && pass || fail "tool name not in message"

begin_test "permission-denied-advisor: includes command in message for Bash"
INPUT='{"tool_name":"Bash","tool_input":{"command":"git push --force origin main"},"cwd":"/tmp"}'
OUT=$(printf '%s' "$INPUT" | bash "$HOOK" 2>/dev/null)
echo "$OUT" | grep -qi "git push\|force" && pass || fail "command not included"

begin_test "permission-denied-advisor: includes file path for Write"
INPUT='{"tool_name":"Write","tool_input":{"file_path":"/etc/passwd"},"cwd":"/tmp"}'
OUT=$(printf '%s' "$INPUT" | bash "$HOOK" 2>/dev/null)
echo "$OUT" | grep -qi "passwd\|etc" && pass || fail "file path not included"

begin_test "permission-denied-advisor: includes do-not-retry instruction"
INPUT='{"tool_name":"Bash","tool_input":{"command":"sudo rm /var/log"},"cwd":"/tmp"}'
OUT=$(printf '%s' "$INPUT" | bash "$HOOK" 2>/dev/null)
echo "$OUT" | grep -qi "retry\|ask\|directly" && pass || fail "no retry instruction"

begin_test "permission-denied-advisor: no output when tool_name missing"
INPUT='{"tool_input":{"command":"echo hi"},"cwd":"/tmp"}'
OUT=$(printf '%s' "$INPUT" | bash "$HOOK" 2>/dev/null)
[ -z "$OUT" ] && pass || fail "should produce no output when tool_name missing"

begin_test "permission-denied-advisor: no output for malformed input"
OUT=$(printf '{}' | bash "$HOOK" 2>/dev/null)
[ -z "$OUT" ] && pass || fail "should produce no output for empty input"

report
