#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

HOOK="$REPO_DIR/hooks/bash-output-compactor.sh"

echo "=== bash-output-compactor Tests ==="

export SUPERCHARGER_NO_DEDUP=1

begin_test "bash-output-compactor: hook exists and is executable"
[ -x "$HOOK" ] && pass || fail "hook missing or not executable"

begin_test "bash-output-compactor: short output passes through unchanged"
INPUT='{"tool_name":"Bash","tool_input":{"command":"git log --oneline -3"},"tool_response":{"stdout":"abc def\nghi jkl\nmno pqr"},"cwd":"/tmp"}'
OUT=$(echo "$INPUT" | bash "$HOOK" 2>/dev/null)
[ -z "$OUT" ] && pass || fail "expected no compaction for 3-line output, got: $OUT"

begin_test "bash-output-compactor: long git log compacted with head + tail"
LONG_LOG=""
for i in $(seq 1 60); do LONG_LOG="$LONG_LOG abc${i} commit ${i}\n"; done
LONG_LOG=$(printf '%b' "$LONG_LOG")
LOG_JSON=$(printf '%s' "$LONG_LOG" | jq -Rs '.')
INPUT=$(printf '{"tool_name":"Bash","tool_input":{"command":"git log --all"},"tool_response":{"stdout":%s},"cwd":"/tmp"}' "$LOG_JSON")
OUT=$(echo "$INPUT" | bash "$HOOK" 2>/dev/null)
echo "$OUT" | grep -q 'updatedToolOutput' && echo "$OUT" | grep -q 'commits omitted' && pass || fail "expected git-log compaction, got: $OUT"

begin_test "bash-output-compactor: long pytest output compacted to summary"
LONG_TEST=""
for i in $(seq 1 60); do LONG_TEST="${LONG_TEST}tests/test_module.py::test_case_${i} ok\n"; done
LONG_TEST="${LONG_TEST}============================== 60 passed in 2.34s ==============================\n"
LONG_TEST=$(printf '%b' "$LONG_TEST")
TEST_JSON=$(printf '%s' "$LONG_TEST" | jq -Rs '.')
INPUT=$(printf '{"tool_name":"Bash","tool_input":{"command":"pytest tests/"},"tool_response":{"stdout":%s},"cwd":"/tmp"}' "$TEST_JSON")
OUT=$(echo "$INPUT" | bash "$HOOK" 2>/dev/null)
echo "$OUT" | grep -q 'Test summary' && echo "$OUT" | grep -q '60 passed' && pass || fail "expected test summary, got: $OUT"

begin_test "bash-output-compactor: failing test keeps failure excerpt"
FAIL_TEST="test_one PASSED\ntest_two FAILED\nAssertionError: expected 1 == 2\n"
for i in $(seq 1 50); do FAIL_TEST="$FAIL_TEST test_$i passed\n"; done
FAIL_TEST="$FAIL_TEST 1 failed, 50 passed in 1.5s"
FAIL_TEST=$(printf '%b' "$FAIL_TEST")
TEST_JSON=$(printf '%s' "$FAIL_TEST" | jq -Rs '.')
INPUT=$(printf '{"tool_name":"Bash","tool_input":{"command":"pytest tests/"},"tool_response":{"stdout":%s},"cwd":"/tmp"}' "$TEST_JSON")
OUT=$(echo "$INPUT" | bash "$HOOK" 2>/dev/null)
echo "$OUT" | grep -q 'Failure excerpt' && pass || fail "expected failure excerpt, got: $OUT"

begin_test "bash-output-compactor: long npm install compacted"
LONG_INSTALL=""
for i in $(seq 1 60); do LONG_INSTALL="$LONG_INSTALL added pkg-$i\n"; done
LONG_INSTALL="$LONG_INSTALL added 60 packages in 3.4s"
LONG_INSTALL=$(printf '%b' "$LONG_INSTALL")
INSTALL_JSON=$(printf '%s' "$LONG_INSTALL" | jq -Rs '.')
INPUT=$(printf '{"tool_name":"Bash","tool_input":{"command":"npm install"},"tool_response":{"stdout":%s},"cwd":"/tmp"}' "$INSTALL_JSON")
OUT=$(echo "$INPUT" | bash "$HOOK" 2>/dev/null)
echo "$OUT" | grep -q 'Install summary' && pass || fail "expected install summary, got: $OUT"

begin_test "bash-output-compactor: skips non-Bash tools"
INPUT='{"tool_name":"Read","tool_input":{"file_path":"/tmp/foo"},"tool_response":{"stdout":"long output"},"cwd":"/tmp"}'
OUT=$(echo "$INPUT" | bash "$HOOK" 2>/dev/null)
[ -z "$OUT" ] && pass || fail "expected silent on Read, got: $OUT"

begin_test "bash-output-compactor: skips unknown command patterns"
LONG=""
for i in $(seq 1 100); do LONG="${LONG}line $i\n"; done
LONG=$(printf '%b' "$LONG")
JSON=$(printf '%s' "$LONG" | jq -Rs '.')
INPUT=$(printf '{"tool_name":"Bash","tool_input":{"command":"ls -la /usr/bin"},"tool_response":{"stdout":%s},"cwd":"/tmp"}' "$JSON")
OUT=$(echo "$INPUT" | bash "$HOOK" 2>/dev/null)
[ -z "$OUT" ] && pass || fail "expected silent on ls (not in pattern list), got: $OUT"

begin_test "bash-output-compactor: SUPERCHARGER_BASH_COMPACTOR=0 disables hook"
LONG_LOG=""
for i in $(seq 1 60); do LONG_LOG="$LONG_LOG abc${i} commit ${i}\n"; done
LONG_LOG=$(printf '%b' "$LONG_LOG")
LOG_JSON=$(printf '%s' "$LONG_LOG" | jq -Rs '.')
INPUT=$(printf '{"tool_name":"Bash","tool_input":{"command":"git log --all"},"tool_response":{"stdout":%s},"cwd":"/tmp"}' "$LOG_JSON")
OUT=$(SUPERCHARGER_BASH_COMPACTOR=0 bash -c "echo '$INPUT' | bash $HOOK" 2>/dev/null)
[ -z "$OUT" ] && pass || fail "expected disabled output, got: $OUT"

report
