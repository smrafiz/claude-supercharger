#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

TOOL="$REPO_DIR/tools/scope-cleanup.sh"

echo "=== Scope Cleanup Tool Tests ==="

# Portable backdate helpers — try GNU touch -d (Linux), fallback to BSD touch -A (macOS).
backdate_2h() {
  local f="$1"
  if command -v gtouch >/dev/null 2>&1; then
    gtouch -d "2 hours ago" "$f"; return
  fi
  if touch -d "2 hours ago" "$f" 2>/dev/null; then return; fi
  if touch -A -020000 "$f" 2>/dev/null; then return; fi
}

backdate_10d() {
  local f="$1"
  if command -v gtouch >/dev/null 2>&1; then
    gtouch -d "10 days ago" "$f"; return
  fi
  if touch -d "10 days ago" "$f" 2>/dev/null; then return; fi
  # BSD: use -t with absolute timestamp
  local ts=$(date -v-10d +%Y%m%d%H%M 2>/dev/null)
  [ -n "$ts" ] && touch -t "$ts" "$f" 2>/dev/null
}

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
backdate_2h "$SCOPE/.dedup-old-hook"
touch "$SCOPE/.dedup-fresh-hook"
bash "$TOOL" --apply >/dev/null 2>&1
[ ! -f "$SCOPE/.dedup-old-hook" ] && [ -f "$SCOPE/.dedup-fresh-hook" ] && pass || fail "old dedup not removed or fresh removed"
cleanup_scope

begin_test "scope-cleanup: removes old agent-classified files (>7d)"
setup_scope
SCOPE="$HOME/.claude/supercharger/scope"
touch "$SCOPE/.agent-classified-old"
backdate_10d "$SCOPE/.agent-classified-old"
touch "$SCOPE/.agent-classified-fresh"
bash "$TOOL" --apply >/dev/null 2>&1
[ ! -f "$SCOPE/.agent-classified-old" ] && [ -f "$SCOPE/.agent-classified-fresh" ] && pass || fail "TTL respected only on dedup, not agent-classified"
cleanup_scope

begin_test "scope-cleanup: dry run reports without deleting"
setup_scope
SCOPE="$HOME/.claude/supercharger/scope"
touch "$SCOPE/.dedup-x"
backdate_2h "$SCOPE/.dedup-x"
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
  backdate_10d "$SCOPE/.$p-old"
done
bash "$TOOL" --apply >/dev/null 2>&1
ALL_GONE=1
for p in router-hash last-tier last-category; do
  [ -f "$SCOPE/.$p-old" ] && ALL_GONE=0
done
[ "$ALL_GONE" = "1" ] && pass || fail "router-hash/last-tier/last-category not all removed"
cleanup_scope

report
