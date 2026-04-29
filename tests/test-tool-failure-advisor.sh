#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

HOOK="$REPO_DIR/hooks/tool-failure-advisor.sh"

echo "=== Tool Failure Advisor Tests ==="

export SUPERCHARGER_NO_DEDUP=1

begin_test "tool-failure-advisor: emits systemMessage for Bash failure"
INPUT='{"tool_name":"Bash","error":"No such file or directory","tool_input":{"command":"cat /nonexistent"},"cwd":"/tmp"}'
OUT=$(printf '%s' "$INPUT" | bash "$HOOK" 2>/dev/null)
echo "$OUT" | grep -q "systemMessage" && pass || fail "no systemMessage for Bash failure"

begin_test "tool-failure-advisor: includes tool name in message"
INPUT='{"tool_name":"Bash","error":"command not found: foobar","tool_input":{"command":"foobar"},"cwd":"/tmp"}'
OUT=$(printf '%s' "$INPUT" | bash "$HOOK" 2>/dev/null)
echo "$OUT" | grep -qi "Bash\|foobar" && pass || fail "tool name not in message"

begin_test "tool-failure-advisor: includes hint for permission denied"
INPUT='{"tool_name":"Bash","error":"permission denied","tool_input":{"command":"rm /etc/hosts"},"cwd":"/tmp"}'
OUT=$(printf '%s' "$INPUT" | bash "$HOOK" 2>/dev/null)
echo "$OUT" | grep -qi "permission\|sudo" && pass || fail "no permission hint"

begin_test "tool-failure-advisor: includes hint for Read not found"
INPUT='{"tool_name":"Read","error":"no such file or directory: /nonexistent.txt","tool_input":{"file_path":"/nonexistent.txt"},"cwd":"/tmp"}'
OUT=$(printf '%s' "$INPUT" | bash "$HOOK" 2>/dev/null)
echo "$OUT" | grep -qi "Glob\|path\|correct" && pass || fail "no path hint for Read"

begin_test "tool-failure-advisor: includes hint for WebFetch 404"
INPUT='{"tool_name":"WebFetch","error":"404 not found","tool_input":{"url":"https://example.com/missing"},"cwd":"/tmp"}'
OUT=$(printf '%s' "$INPUT" | bash "$HOOK" 2>/dev/null)
echo "$OUT" | grep -qi "URL\|not found\|correct" && pass || fail "no URL hint for WebFetch 404"

begin_test "tool-failure-advisor: includes duration_ms when slow"
INPUT='{"tool_name":"WebFetch","error":"connection timeout","tool_input":{"url":"https://slow.example.com"},"duration_ms":8000,"cwd":"/tmp"}'
OUT=$(printf '%s' "$INPUT" | bash "$HOOK" 2>/dev/null)
echo "$OUT" | grep -qi "8000\|slow\|Duration" && pass || fail "slow duration not noted"

begin_test "tool-failure-advisor: no output when error is empty"
INPUT='{"tool_name":"Bash","error":"","tool_input":{"command":"echo hi"},"cwd":"/tmp"}'
OUT=$(printf '%s' "$INPUT" | bash "$HOOK" 2>/dev/null)
[ -z "$OUT" ] && pass || fail "should produce no output when error is empty"

begin_test "tool-failure-advisor: no output for malformed input"
OUT=$(printf '{}' | bash "$HOOK" 2>/dev/null)
[ -z "$OUT" ] && pass || fail "should produce no output for empty input"

unset SUPERCHARGER_NO_DEDUP
report
