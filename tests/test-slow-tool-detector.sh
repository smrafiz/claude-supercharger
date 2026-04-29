#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

HOOK="$REPO_DIR/hooks/slow-tool-detector.sh"

echo "=== Slow Tool Detector Tests ==="

export SUPERCHARGER_NO_DEDUP=1

begin_test "slow-tool-detector: warns for slow Bash command"
INPUT='{"tool_name":"Bash","duration_ms":15000,"tool_input":{"command":"find / -name foo"},"cwd":"/tmp"}'
OUT=$(printf '%s' "$INPUT" | bash "$HOOK" 2>/dev/null)
echo "$OUT" | grep -q "systemMessage" && pass || fail "no systemMessage for slow Bash"

begin_test "slow-tool-detector: includes duration in message"
INPUT='{"tool_name":"Bash","duration_ms":15000,"tool_input":{"command":"sleep 15"},"cwd":"/tmp"}'
OUT=$(printf '%s' "$INPUT" | bash "$HOOK" 2>/dev/null)
echo "$OUT" | grep -q "15.0s\|15s" && pass || fail "duration not in message"

begin_test "slow-tool-detector: no output for fast Bash"
INPUT='{"tool_name":"Bash","duration_ms":500,"tool_input":{"command":"echo hi"},"cwd":"/tmp"}'
OUT=$(printf '%s' "$INPUT" | bash "$HOOK" 2>/dev/null)
[ -z "$OUT" ] && pass || fail "should not warn for fast command"

begin_test "slow-tool-detector: warns for slow WebFetch"
INPUT='{"tool_name":"WebFetch","duration_ms":10000,"tool_input":{"url":"https://slow.example.com"},"cwd":"/tmp"}'
OUT=$(printf '%s' "$INPUT" | bash "$HOOK" 2>/dev/null)
echo "$OUT" | grep -qi "slow\|network\|cached" && pass || fail "no WebFetch slow hint"

begin_test "slow-tool-detector: warns for slow Read"
INPUT='{"tool_name":"Read","duration_ms":5000,"tool_input":{"file_path":"/large/file.log"},"cwd":"/tmp"}'
OUT=$(printf '%s' "$INPUT" | bash "$HOOK" 2>/dev/null)
echo "$OUT" | grep -q "systemMessage" && pass || fail "no systemMessage for slow Read"

begin_test "slow-tool-detector: no output when duration_ms absent"
INPUT='{"tool_name":"Bash","tool_input":{"command":"echo hi"},"cwd":"/tmp"}'
OUT=$(printf '%s' "$INPUT" | bash "$HOOK" 2>/dev/null)
[ -z "$OUT" ] && pass || fail "should produce no output when duration_ms absent"

begin_test "slow-tool-detector: no output for malformed input"
OUT=$(printf '{}' | bash "$HOOK" 2>/dev/null)
[ -z "$OUT" ] && pass || fail "should produce no output for empty input"

begin_test "slow-tool-detector: fast WebFetch below threshold produces no output"
INPUT='{"tool_name":"WebFetch","duration_ms":2000,"tool_input":{"url":"https://fast.example.com"},"cwd":"/tmp"}'
OUT=$(printf '%s' "$INPUT" | bash "$HOOK" 2>/dev/null)
[ -z "$OUT" ] && pass || fail "should not warn for fast WebFetch"

unset SUPERCHARGER_NO_DEDUP
report
