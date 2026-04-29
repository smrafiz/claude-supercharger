#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

TOOL="$REPO_DIR/tools/scope-cleanup.sh"

echo "=== Scope Cleanup Tool Tests ==="

setup_scope() {
  setup_test_home
  mkdir -p "$HOME/.claude/supercharger/scope"
}

cleanup_scope() {
  teardown_test_home
}

begin_test "scope-cleanup: removes old dedup files (>1h)"
setup_scope
SCOPE="$HOME/.claude/supercharger/scope"
touch "$SCOPE/.dedup-old-hook"
touch -A -020000 "$SCOPE/.dedup-old-hook" 2>/dev/null || touch -d "2 hours ago" "$SCOPE/.dedup-old-hook" 2>/dev/null || true
touch "$SCOPE/.dedup-fresh-hook"
bash "$TOOL" --apply >/dev/null 2>&1
[ ! -f "$SCOPE/.dedup-old-hook" ] && [ -f "$SCOPE/.dedup-fresh-hook" ] && pass || fail "old dedup not removed or fresh removed"
cleanup_scope

begin_test "scope-cleanup: removes old agent-classified files (>7d)"
setup_scope
SCOPE="$HOME/.claude/supercharger/scope"
touch "$SCOPE/.agent-classified-old"
# 10 days ago via fixed timestamp (year-1 forces it old enough)
TENDAY=$(date -v-10d +%Y%m%d%H%M 2>/dev/null || date -d "10 days ago" +%Y%m%d%H%M 2>/dev/null)
[ -n "$TENDAY" ] && touch -t "$TENDAY" "$SCOPE/.agent-classified-old" 2>/dev/null || true
touch "$SCOPE/.agent-classified-fresh"
bash "$TOOL" --apply >/dev/null 2>&1
[ ! -f "$SCOPE/.agent-classified-old" ] && [ -f "$SCOPE/.agent-classified-fresh" ] && pass || fail "TTL respected only on dedup, not agent-classified"
cleanup_scope

begin_test "scope-cleanup: dry run reports without deleting"
setup_scope
SCOPE="$HOME/.claude/supercharger/scope"
touch "$SCOPE/.dedup-x"
touch -A -020000 "$SCOPE/.dedup-x" 2>/dev/null || touch -d "2 hours ago" "$SCOPE/.dedup-x" 2>/dev/null || true
OUT=$(bash "$TOOL" 2>&1)
echo "$OUT" | grep -q "would remove" && [ -f "$SCOPE/.dedup-x" ] && pass || fail "dry run deleted or no report"
cleanup_scope

begin_test "scope-cleanup: handles missing scope dir"
setup_test_home
OUT=$(bash "$TOOL" 2>&1)
echo "$OUT" | grep -q "scope dir not found" && pass || fail "missing dir not handled"
teardown_test_home

begin_test "scope-cleanup: covers .router-hash, .last-tier, .last-category"
setup_scope
SCOPE="$HOME/.claude/supercharger/scope"
for p in router-hash last-tier last-category; do
  touch "$SCOPE/.$p-old"
  TENDAY=$(date -v-10d +%Y%m%d%H%M 2>/dev/null || date -d "10 days ago" +%Y%m%d%H%M 2>/dev/null)
  [ -n "$TENDAY" ] && touch -t "$TENDAY" "$SCOPE/.$p-old" 2>/dev/null || true
done
bash "$TOOL" --apply >/dev/null 2>&1
ALL_GONE=1
for p in router-hash last-tier last-category; do
  [ -f "$SCOPE/.$p-old" ] && ALL_GONE=0
done
[ "$ALL_GONE" = "1" ] && pass || fail "router-hash/last-tier/last-category not all removed"
cleanup_scope

report
