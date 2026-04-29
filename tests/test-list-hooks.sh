#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

TOOL="$REPO_DIR/tools/list-hooks.sh"

echo "=== List Hooks Tool Tests ==="

begin_test "list-hooks: outputs markdown header"
OUT=$(bash "$TOOL" 2>/dev/null)
echo "$OUT" | grep -q "^# Supercharger Hook Catalog" && pass || fail "no markdown header"

begin_test "list-hooks: includes a hook table"
OUT=$(bash "$TOOL" 2>/dev/null)
echo "$OUT" | grep -q "| Hook | Event | Matcher | Purpose |" && pass || fail "no hook table header"

begin_test "list-hooks: lists safety hook"
OUT=$(bash "$TOOL" 2>/dev/null)
echo "$OUT" | grep -q "| \`safety\` |" && pass || fail "safety hook not listed"

begin_test "list-hooks: lists git-safety hook"
OUT=$(bash "$TOOL" 2>/dev/null)
echo "$OUT" | grep -q "| \`git-safety\` |" && pass || fail "git-safety hook not listed"

begin_test "list-hooks: skips lib-suppress (helper, not hook)"
OUT=$(bash "$TOOL" 2>/dev/null)
echo "$OUT" | grep -q "| \`lib-suppress\` |" && fail "lib-suppress should be skipped" || pass

begin_test "list-hooks: includes tools section"
OUT=$(bash "$TOOL" 2>/dev/null)
echo "$OUT" | grep -q "## Standalone tools" && pass || fail "no standalone tools section"

begin_test "list-hooks: lists scope-cleanup tool"
OUT=$(bash "$TOOL" 2>/dev/null)
echo "$OUT" | grep -q "| \`tools/scope-cleanup.sh\` |" && pass || fail "scope-cleanup not listed"

begin_test "list-hooks: extracts Event field correctly"
OUT=$(bash "$TOOL" 2>/dev/null)
# safety.sh has "Event: PreToolUse"
echo "$OUT" | grep "| \`safety\` |" | grep -q "PreToolUse" && pass || fail "safety should have PreToolUse event"

begin_test "list-hooks: lists at least 50 hooks"
OUT=$(bash "$TOOL" 2>/dev/null)
COUNT=$(echo "$OUT" | grep -cE '^\| `[a-z-]+` \|')
[ "$COUNT" -ge 50 ] && pass || fail "expected >= 50 hook rows, got $COUNT"

report
