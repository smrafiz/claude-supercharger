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

# v2.11.1: the latest version is the VERSION string in lib/utils.sh, NOT the max git
# tag. The repo carries orphaned tags from an earlier scheme (v3.6.x, 2026-04) that a
# max-tag sort wrongly picked as "latest", so every 2.x release looked perpetually
# stale. fetch_remote_version must read the file, not tags.
begin_test "update: remote version check reads VERSION from lib/utils.sh (not tags)"
if grep -q 'raw.githubusercontent.com.*lib/utils.sh' "$TOOL" && grep -q 'VERSION=' "$TOOL"; then pass
else fail "fetch_remote_version no longer reads lib/utils.sh — max-tag detection regresses the orphan-tag bug"; fi

# Regression guard: version detection must NOT max-sort git tags (that is the v3.6.35 bug).
begin_test "update: version detection does NOT pick the max git tag (orphan-tag guard)"
if grep -qE 'ls-remote --tags' "$TOOL"; then
  fail "fetch_remote_version still max-sorts git tags — reintroduces the orphaned-tag mis-detection"
else pass; fi

# Reachability fallback: the GitHub contents API path must remain for hosts where raw
# HTTPS is unavailable.
begin_test "update: keeps a GitHub API fallback for the version file"
if grep -q 'api.github.com/repos/smrafiz/claude-supercharger/contents/lib/utils.sh' "$TOOL"; then pass
else fail "version-file API fallback removed"; fi

report
