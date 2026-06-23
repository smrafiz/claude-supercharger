#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

HOOK="$REPO_DIR/hooks/update-check.sh"

echo "=== Update Check Tests ==="

begin_test "update-check: respects SUPERCHARGER_NO_UPDATE_CHECK=1"
setup_test_home
mkdir -p "$HOOK_DUMMY=$HOME/.claude/supercharger"
mkdir -p "$HOME/.claude/supercharger"
echo "2.6.77" > "$HOME/.claude/supercharger/.version"
OUT=$(SUPERCHARGER_NO_UPDATE_CHECK=1 bash "$HOOK" 2>&1)
EXIT=$?
teardown_test_home
[ "$EXIT" -eq 0 ] && [ -z "$OUT" ] && pass || fail "expected silent exit, exit=$EXIT out=$OUT"

begin_test "update-check: exits 0 with no .version file"
setup_test_home
mkdir -p "$HOME/.claude/supercharger"
OUT=$(bash "$HOOK" 2>&1)
EXIT=$?
teardown_test_home
[ "$EXIT" -eq 0 ] && pass || fail "exit=$EXIT out=$OUT"

begin_test "update-check: uses cache when fresh (<24h)"
setup_test_home
mkdir -p "$HOME/.claude/supercharger"
echo "2.6.77" > "$HOME/.claude/supercharger/.version"
echo "2.6.77" > "$HOME/.claude/supercharger/.update-cache"
# Force cache freshness — touch to now
touch "$HOME/.claude/supercharger/.update-cache"
START=$(date +%s)
OUT=$(SUPERCHARGER_NO_UPDATE_CHECK=0 bash "$HOOK" 2>&1)
END=$(date +%s)
EXIT=$?
teardown_test_home
# Should return fast (no network) — and silent (LOCAL == REMOTE)
[ "$EXIT" -eq 0 ] && [ -z "$OUT" ] && [ "$((END - START))" -lt 3 ] && pass || fail "exit=$EXIT out=$OUT time=$((END - START))s"

begin_test "update-check: prints banner when cache shows newer version"
setup_test_home
mkdir -p "$HOME/.claude/supercharger"
echo "2.6.77" > "$HOME/.claude/supercharger/.version"
echo "9.9.9" > "$HOME/.claude/supercharger/.update-cache"
touch "$HOME/.claude/supercharger/.update-cache"
OUT=$(bash "$HOOK" 2>&1)
EXIT=$?
teardown_test_home
[ "$EXIT" -eq 0 ] && echo "$OUT" | grep -q "Supercharger update" && pass || fail "no banner, exit=$EXIT out=$OUT"

begin_test "update-check: cache miss when stale (>24h)"
setup_test_home
mkdir -p "$HOME/.claude/supercharger"
echo "2.6.77" > "$HOME/.claude/supercharger/.version"
echo "2.6.77" > "$HOME/.claude/supercharger/.update-cache"
# Backdate cache to >24h ago
touch -t 202001010000 "$HOME/.claude/supercharger/.update-cache" 2>/dev/null
# Hook should NOT exit on cache (proceed to fetch) — but the fetch is
# backgrounded and non-blocking, so the foreground still returns ~immediately.
START=$(date +%s)
OUT=$(timeout 6 bash "$HOOK" 2>&1)
END=$(date +%s)
EXIT=$?
teardown_test_home
# Background fetch shouldn't block past a few seconds
[ "$((END - START))" -lt 6 ] && pass || fail "stale path blocked too long: $((END - START))s"

report
