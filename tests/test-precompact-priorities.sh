#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

HOOK="$REPO_DIR/hooks/precompact-priorities.sh"

echo "=== PreCompact Priorities Tests ==="

begin_test "precompact-priorities: emits priority preservation block"
OUT=$(echo '{}' | bash "$HOOK" 2>/dev/null)
echo "$OUT" | grep -q "priority-preservation-instructions" && pass || fail "no priority block"

begin_test "precompact-priorities: includes UNANSWERED QUESTIONS section"
OUT=$(echo '{}' | bash "$HOOK" 2>/dev/null)
echo "$OUT" | grep -q "UNANSWERED QUESTIONS" && pass || fail "missing UNANSWERED QUESTIONS section"

begin_test "precompact-priorities: includes ROOT CAUSES section"
OUT=$(echo '{}' | bash "$HOOK" 2>/dev/null)
echo "$OUT" | grep -q "ROOT CAUSES" && pass || fail "missing ROOT CAUSES section"

begin_test "precompact-priorities: includes EXACT NUMBERS section"
OUT=$(echo '{}' | bash "$HOOK" 2>/dev/null)
echo "$OUT" | grep -q "EXACT NUMBERS" && pass || fail "missing EXACT NUMBERS section"

begin_test "precompact-priorities: includes SUBAGENT FINDINGS section"
OUT=$(echo '{}' | bash "$HOOK" 2>/dev/null)
echo "$OUT" | grep -q "SUBAGENT FINDINGS" && pass || fail "missing SUBAGENT FINDINGS section"

begin_test "precompact-priorities: includes SUPERCHARGER STATE section"
OUT=$(echo '{}' | bash "$HOOK" 2>/dev/null)
echo "$OUT" | grep -q "SUPERCHARGER STATE" && pass || fail "missing SUPERCHARGER STATE section"

begin_test "precompact-priorities: drains stdin without error"
OUT=$(echo '{"trigger":"manual"}' | bash "$HOOK" 2>/dev/null)
[ -n "$OUT" ] && pass || fail "no output with json input"

begin_test "precompact-priorities: respects disabled flag"
setup_test_home
mkdir -p "$HOME/.claude/supercharger/scope"
printf 'precompact-priorities\n' > "$HOME/.claude/supercharger/scope/.disabled-hooks"
OUT=$(echo '{}' | bash "$HOOK" 2>/dev/null)
[ -z "$OUT" ] && pass || fail "should suppress when disabled"
teardown_test_home

report
