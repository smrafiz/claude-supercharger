#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

HOOK="$REPO_DIR/hooks/update-check.sh"

echo "=== Update Check Tests ==="

begin_test "update-check: respects SUPERCHARGER_NO_UPDATE_CHECK=1"
setup_test_home
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

# --- v4.0.32: the banner must land on STDOUT ---------------------------------
# For the life of this hook the banner went to stderr and was never delivered to
# anyone. The check ran, the network call completed, the cache was written, the
# comparison took the banner branch — and the output went nowhere. Proven on
# 2026-09-07 against a live install: the cache regenerated to 4.0.31 against an
# installed 4.0.30 and the user saw nothing.
#
# Twelve tests above assert the banner is PRODUCED. Every one of them captured
# both streams together, so all twelve passed while the feature did nothing.
# That is the whole lesson: assert the CHANNEL, not just the content.
# [[diagnostic-must-reach-observer]]
_UCS_TD=$(mktemp -d); mkdir -p "$_UCS_TD/state"
printf '4.0.20\n' > "$_UCS_TD/state/.version"
printf '4.0.31\n' > "$_UCS_TD/state/.update-cache"
_ucs() { SUPERCHARGER_STATE="$_UCS_TD/state" SUPERCHARGER_HOME="$REPO_DIR" \
           bash "$REPO_DIR/hooks/update-check.sh" "$@"; }

begin_test "update-check: the banner is on STDOUT"
[ -n "$(_ucs 2>/dev/null)" ] && pass || fail "nothing on stdout — the banner is undeliverable"

begin_test "update-check: and NOT on stderr"
# The control. Without it the test above also passes when the banner is on both.
[ -z "$(_ucs 2>&1 1>/dev/null)" ] && pass || fail "still writing to stderr, which SessionStart does not deliver"

begin_test "update-check: no stderr writes remain in the source"
! grep -q '>&2' "$REPO_DIR/hooks/update-check.sh" && pass \
  || fail "a >&2 came back — SessionStart stderr is not delivered"
rm -rf "$_UCS_TD"

begin_test "the /memory-prune nudge is a nudge, not a trace, so it is on stdout"
# Second instance of the same defect, found by auditing siblings rather than
# assuming one. The two "injected ..." lines in that hook stay on stderr on
# purpose — they are traces. A blanket stderr ban would be the wrong fix.
grep -q 'run /memory-prune to archive\."$' "$REPO_DIR/hooks/session-memory-inject.sh" && pass \
  || fail "the memory-prune nudge is back on stderr"

report
