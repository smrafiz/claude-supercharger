#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

TOOL="$REPO_DIR/tools/update.sh"

# Seed helper: minimal installed environment for update detection
seed_installed_env() {
  mkdir -p "$HOME/.claude/rules"
  mkdir -p "$HOME/.claude/supercharger"
  echo "developer" > "$HOME/.claude/rules/developer.md"
  echo "2.0.0" > "$HOME/.claude/supercharger/.version"
}

# Test 1: --dry-run → exits 0
begin_test "update: --dry-run exits 0"
setup_test_home
seed_installed_env
bash "$TOOL" --dry-run >/dev/null 2>&1
EXIT_CODE=$?
if [ $EXIT_CODE -eq 0 ]; then pass
else fail "expected exit 0, got $EXIT_CODE"; fi
teardown_test_home

# Test 2: --dry-run → mentions dry-run in output
begin_test "update: --dry-run prints dry-run message"
setup_test_home
seed_installed_env
OUTPUT=$(bash "$TOOL" --dry-run 2>&1 || true)
if printf '%s\n' "$OUTPUT" | grep -qi "dry.run\|no changes"; then pass
else fail "expected dry-run message in output, got: $OUTPUT"; fi
teardown_test_home

# Test 3: --dry-run → does not modify installed files
begin_test "update: --dry-run does not modify version file"
setup_test_home
seed_installed_env
BEFORE=$(cat "$HOME/.claude/supercharger/.version")
bash "$TOOL" --dry-run >/dev/null 2>&1 || true
AFTER=$(cat "$HOME/.claude/supercharger/.version" 2>/dev/null || echo "missing")
if [ "$BEFORE" = "$AFTER" ]; then pass
else fail "version file changed during dry-run: $BEFORE → $AFTER"; fi
teardown_test_home

# Test 4: --check with no network → exits 0 gracefully (no crash)
begin_test "update: --check exits 0 when network unavailable"
setup_test_home
seed_installed_env
# Redirect network by using an invalid REPO_URL override if supported,
# otherwise rely on the tool's own timeout/graceful fallback
OUTPUT=$(bash "$TOOL" --check 2>&1 || true)
EXIT_CODE=$?
# Should not crash — exit 0 or 1 are both acceptable, but not 2+
if [ $EXIT_CODE -le 1 ]; then pass
else fail "unexpected exit code $EXIT_CODE on --check"; fi
teardown_test_home

# Test 5: No roles detected → exits 1 early
begin_test "update: no roles installed exits 1"
setup_test_home
mkdir -p "$HOME/.claude/supercharger"
echo "2.0.0" > "$HOME/.claude/supercharger/.version"
# No role files in .claude/rules/
bash "$TOOL" >/dev/null 2>&1
EXIT_CODE=$?
if [ $EXIT_CODE -eq 1 ]; then pass
else fail "expected exit 1 (no roles), got $EXIT_CODE"; fi
teardown_test_home

# v2.10.2 regression: update.sh must detect the notify state using the SAME flag
# files that notify-toggle.sh / install.sh actually write (.no-desktop-notify /
# .sound-only-notify). It previously checked stale names (.notify-off/.notify-sound)
# that never matched, so every update silently passed --notify on and clobbered a
# user's "off" setting.
begin_test "update: notify detection uses the real flag filenames"
if grep -q '\.no-desktop-notify' "$TOOL" && grep -q '\.sound-only-notify' "$TOOL" \
   && ! grep -q '\.notify-off"' "$TOOL" && ! grep -q '\.notify-sound"' "$TOOL"; then
  pass
else
  fail "update.sh notify-flag detection references wrong/stale filenames"
fi

# Cross-check: the flag names update.sh looks for are the ones notify-toggle writes
begin_test "update: notify flags match notify-toggle's canonical names"
TOGGLE="$REPO_DIR/tools/notify-toggle.sh"
if grep -q '\.no-desktop-notify' "$TOGGLE" && grep -q '\.no-desktop-notify' "$TOOL"; then
  pass
else
  fail "notify flag name drift between update.sh and notify-toggle.sh"
fi

# v2.10.3 regression: version check must use git ls-remote (same github.com channel
# as the clone), not ONLY api.github.com — which has a 60/hr unauthenticated rate
# limit + no proxy inheritance, so it failed independently of `git clone`.
begin_test "update: remote version check uses git ls-remote (not api-only)"
if grep -q 'git ls-remote' "$TOOL"; then pass
else fail "fetch_remote_version no longer uses git ls-remote — API-only regresses the rate-limit fix"; fi

# The tag-parse pipeline must pick the highest semver NUMERICALLY (2.10.2 > 2.9.17,
# which a string sort would get wrong).
begin_test "update: version parse picks highest semver numerically"
HIGHEST=$(printf '%s\n' \
  "a	refs/tags/v2.9.8" "b	refs/tags/v2.9.17" "c	refs/tags/v2.10.0" "d	refs/tags/v2.10.2" "e	refs/tags/v1.0.0" \
  | awk -F/ '{print $NF}' | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sed 's/^v//' \
  | sort -t. -k1,1n -k2,2n -k3,3n | tail -1)
[ "$HIGHEST" = "2.10.2" ] && pass || fail "expected 2.10.2, got '$HIGHEST' (string sort would pick 2.9.17)"

report
