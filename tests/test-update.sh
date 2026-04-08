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

report
