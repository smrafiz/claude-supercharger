#!/usr/bin/env bash
# Tests for the /sc activate-deactivate toggle (v2.9.0):
#   tools/sc-toggle.sh off|on|status  +  the shared-lib kill-switch early-exit.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

TOGGLE="$REPO_DIR/tools/sc-toggle.sh"

echo "=== sc-toggle (activate/deactivate) Tests ==="

# Build an isolated ~/.claude with the deployed lib + a CLAUDE.md managed block.
_setup() {
  setup_test_home
  mkdir -p "$HOME/.claude/supercharger/scope" "$HOME/.claude/supercharger/hooks" "$HOME/.claude/backups"
  cp "$REPO_DIR/hooks/lib-suppress.sh" "$HOME/.claude/supercharger/hooks/" 2>/dev/null || true
  cp "$REPO_DIR/hooks/lib-timing.sh"   "$HOME/.claude/supercharger/hooks/" 2>/dev/null || true
  # merge-style CLAUDE.md: user content, then the Supercharger managed block
  printf '# My rules\nUse tabs.\n\n# --- Claude Supercharger\nManaged block line 1\nManaged block line 2\n' > "$HOME/.claude/CLAUDE.md"
}
FLAG_REL=".claude/supercharger/scope/.supercharger-disabled"

begin_test "sc-toggle: status is ACTIVE by default"
_setup
bash "$TOGGLE" status 2>/dev/null | grep -q "ACTIVE" && pass || fail "expected ACTIVE"
teardown_test_home

begin_test "sc-toggle: off sets the kill-switch flag"
_setup
bash "$TOGGLE" off >/dev/null 2>&1
[ -f "$HOME/$FLAG_REL" ] && pass || fail "flag not created"
teardown_test_home

begin_test "sc-toggle: off strips the Supercharger block but keeps user content"
_setup
bash "$TOGGLE" off >/dev/null 2>&1
if grep -q "Use tabs" "$HOME/.claude/CLAUDE.md" && ! grep -q "Managed block" "$HOME/.claude/CLAUDE.md"; then
  pass
else
  fail "expected user content kept + managed block removed, got: $(cat "$HOME/.claude/CLAUDE.md")"
fi
teardown_test_home

begin_test "sc-toggle: off writes a backup"
_setup
bash "$TOGGLE" off >/dev/null 2>&1
ls "$HOME/.claude/backups"/deactivate-* >/dev/null 2>&1 && pass || fail "no backup written"
teardown_test_home

begin_test "sc-toggle: a hook sourcing lib-suppress EXITS immediately when off"
_setup
bash "$TOGGLE" off >/dev/null 2>&1
OUT=$(HOME="$HOME" bash -c '. "$HOME/.claude/supercharger/hooks/lib-suppress.sh"; echo REACHED' 2>/dev/null)
[ "$OUT" != "REACHED" ] && pass || fail "hook did not early-exit (kill-switch ignored)"
teardown_test_home

begin_test "sc-toggle: security hooks (lib-timing) also early-exit when off"
_setup
bash "$TOGGLE" off >/dev/null 2>&1
OUT=$(HOME="$HOME" bash -c '. "$HOME/.claude/supercharger/hooks/lib-timing.sh"; echo REACHED' 2>/dev/null)
[ "$OUT" != "REACHED" ] && pass || fail "security hook did not early-exit"
teardown_test_home

begin_test "sc-toggle: SUPERCHARGER_TOGGLE bypasses the kill-switch (no bootstrap trap)"
_setup
bash "$TOGGLE" off >/dev/null 2>&1
OUT=$(HOME="$HOME" SUPERCHARGER_TOGGLE=1 bash -c '. "$HOME/.claude/supercharger/hooks/lib-suppress.sh"; echo REACHED' 2>/dev/null)
[ "$OUT" = "REACHED" ] && pass || fail "toggle bypass failed — /sc on could strand disabled"
teardown_test_home

begin_test "sc-toggle: status is DISABLED after off"
_setup
bash "$TOGGLE" off >/dev/null 2>&1
bash "$TOGGLE" status 2>/dev/null | grep -qi "DISABLED" && pass || fail "expected DISABLED"
teardown_test_home

begin_test "sc-toggle: on removes the flag"
_setup
bash "$TOGGLE" off >/dev/null 2>&1
bash "$TOGGLE" on >/dev/null 2>&1
[ ! -f "$HOME/$FLAG_REL" ] && pass || fail "flag not removed"
teardown_test_home

begin_test "sc-toggle: on restores the CLAUDE.md block byte-exactly"
_setup
ORIG=$(cat "$HOME/.claude/CLAUDE.md")
bash "$TOGGLE" off >/dev/null 2>&1
bash "$TOGGLE" on >/dev/null 2>&1
[ "$(cat "$HOME/.claude/CLAUDE.md")" = "$ORIG" ] && pass || fail "CLAUDE.md not restored exactly"
teardown_test_home

begin_test "sc-toggle: hook runs normally again after on"
_setup
bash "$TOGGLE" off >/dev/null 2>&1
bash "$TOGGLE" on >/dev/null 2>&1
OUT=$(HOME="$HOME" bash -c '. "$HOME/.claude/supercharger/hooks/lib-suppress.sh"; echo REACHED' 2>/dev/null)
[ "$OUT" = "REACHED" ] && pass || fail "hook still blocked after on"
teardown_test_home

begin_test "sc-toggle: off is idempotent (already off)"
_setup
bash "$TOGGLE" off >/dev/null 2>&1
bash "$TOGGLE" off 2>/dev/null | grep -qi "already OFF" && pass || fail "expected already-OFF message"
teardown_test_home

begin_test "sc-toggle: on is idempotent (already on)"
_setup
bash "$TOGGLE" on 2>/dev/null | grep -qi "already ON" && pass || fail "expected already-ON message"
teardown_test_home

begin_test "sc-toggle: deploy-mode (whole-file CLAUDE.md, marker at line 1) blanks then restores"
setup_test_home
mkdir -p "$HOME/.claude/supercharger/scope" "$HOME/.claude/supercharger/hooks"
cp "$REPO_DIR/hooks/lib-suppress.sh" "$HOME/.claude/supercharger/hooks/" 2>/dev/null || true
printf '# Claude Supercharger v9.9.9\n\n## rules\nbe terse\n' > "$HOME/.claude/CLAUDE.md"
ORIG=$(cat "$HOME/.claude/CLAUDE.md")
bash "$TOGGLE" off >/dev/null 2>&1
BLANK_OK=1; [ -s "$HOME/.claude/CLAUDE.md" ] && BLANK_OK=0
bash "$TOGGLE" on >/dev/null 2>&1
if [ "$BLANK_OK" = 1 ] && [ "$(cat "$HOME/.claude/CLAUDE.md")" = "$ORIG" ]; then pass; else fail "deploy-mode blank/restore failed (blank_ok=$BLANK_OK)"; fi
teardown_test_home

report
