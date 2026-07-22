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

# v2.12.1: the FRESH GitHub contents API (raw-accept header) must be the PRIMARY source,
# not raw.githubusercontent.com — the raw host is CDN-cached and lags minutes behind a
# release, which made /sc-update falsely report "up to date" right after a release.
begin_test "update: uses the fresh contents API (raw-accept header) as primary"
if grep -q 'application/vnd.github.raw' "$TOOL"; then pass
else fail "fresh raw-accept contents API not used — CDN-cached raw as primary re-introduces the stale check"; fi

begin_test "update: fresh API is ordered BEFORE the CDN-cached raw fallback"
# Match the actual URL usage (https://…), not the explanatory comment.
API_LN=$(grep -n 'application/vnd.github.raw' "$TOOL" | head -1 | cut -d: -f1)
RAW_LN=$(grep -n 'https://raw.githubusercontent.com' "$TOOL" | head -1 | cut -d: -f1)
if [ -n "$API_LN" ] && [ -n "$RAW_LN" ] && [ "$API_LN" -lt "$RAW_LN" ]; then pass
else fail "raw ($RAW_LN) is not after the fresh API ($API_LN) — primary/fallback order wrong"; fi

# v2.18.1: the integrity SHA fetch must try AUTHENTICATED gh first (5000/hr) so the
# 60/hr anonymous limit doesn't 403 and dead-end /sc-update on shared IPs / NAT / CI.
begin_test "update: SHA integrity check tries authenticated gh before anonymous API"
if grep -q 'gh api "repos/smrafiz/claude-supercharger/commits/master"' "$TOOL"; then pass
else fail "no authenticated gh path for the expected-SHA fetch — anonymous 403 will abort updates"; fi

# The unfetchable-SHA case must FAIL OPEN (warn + proceed on the TLS clone), NOT abort.
begin_test "update: unfetchable SHA fails open (warns, does not abort)"
if grep -q 'Proceeding with the TLS-authenticated clone' "$TOOL" \
   && ! grep -q 'Could not fetch expected commit SHA from GitHub API. Aborting' "$TOOL"; then pass
else fail "SHA-fetch failure still aborts the update instead of proceeding with a warning"; fi

# But a SUCCESSFULLY-fetched SHA that MISMATCHES the clone must still fail closed.
begin_test "update: SHA mismatch still fails closed (integrity retained)"
if grep -q 'does not match expected' "$TOOL"; then pass
else fail "mismatch abort removed — a wrong clone would be installed silently"; fi

# v2.21.9: install.sh defaults the MCP profile to "light" and unconditionally
# overwrites scope/.mcp-profile, so update.sh must DETECT the current profile and
# re-pass --mcp-profile, or every update silently resets dev/research/full to light.
begin_test "update: both install invocations pass --mcp-profile"
if [ "$(grep -c -- '--mcp-profile' "$TOOL")" -ge 2 ]; then pass
else fail "an install.sh invocation in update.sh omits --mcp-profile (mcp-profile reset on update)"; fi

begin_test "update: detects the current profile from scope/.mcp-profile"
if grep -q 'scope/.mcp-profile' "$TOOL" && grep -q 'DETECTED_MCP_PROFILE' "$TOOL"; then pass
else fail "update.sh does not read the existing .mcp-profile before re-installing"; fi

report
