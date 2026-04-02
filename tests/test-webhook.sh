#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

source "$REPO_DIR/lib/utils.sh"
source "$REPO_DIR/lib/webhook.sh"

# --- Test: webhook_enabled returns false with no config ---
begin_test "webhook: webhook_enabled false when no config"
setup_test_home

if webhook_enabled; then
  fail "expected webhook_enabled to return false"
else
  pass
fi
teardown_test_home

# --- Test: webhook_enabled returns false when disabled ---
begin_test "webhook: webhook_enabled false when disabled"
setup_test_home
mkdir -p "$HOME/.claude/supercharger"
echo '{"platform":"slack","url":"https://example.com","enabled":false}' > "$HOME/.claude/supercharger/webhook.json"

if webhook_enabled; then
  fail "expected webhook_enabled to return false"
else
  pass
fi
teardown_test_home

# --- Test: webhook_enabled returns true when enabled ---
begin_test "webhook: webhook_enabled true when enabled"
setup_test_home
mkdir -p "$HOME/.claude/supercharger"
echo '{"platform":"slack","url":"https://example.com","enabled":true}' > "$HOME/.claude/supercharger/webhook.json"

if webhook_enabled; then
  pass
else
  fail "expected webhook_enabled to return true"
fi
teardown_test_home

# --- Test: webhook-setup.sh status with no config ---
begin_test "webhook: setup status with no config"
setup_test_home
mkdir -p "$HOME/.claude/supercharger"

OUTPUT=$(bash "$REPO_DIR/tools/webhook-setup.sh" status 2>&1)
echo "$OUTPUT" | grep -q "No webhook configured" && pass || fail "expected 'No webhook configured'"
teardown_test_home

# --- Test: webhook-setup.sh enable/disable ---
begin_test "webhook: setup enable and disable"
setup_test_home
mkdir -p "$HOME/.claude/supercharger"
echo '{"platform":"slack","url":"https://example.com","enabled":false}' > "$HOME/.claude/supercharger/webhook.json"

bash "$REPO_DIR/tools/webhook-setup.sh" enable >/dev/null 2>&1
ENABLED=$(WEBHOOK_CONFIG_FILE="$HOME/.claude/supercharger/webhook.json" python3 -c "import json,os; print(json.load(open(os.environ['WEBHOOK_CONFIG_FILE']))['enabled'])")

if [[ "$ENABLED" == "True" ]]; then
  bash "$REPO_DIR/tools/webhook-setup.sh" disable >/dev/null 2>&1
  DISABLED=$(WEBHOOK_CONFIG_FILE="$HOME/.claude/supercharger/webhook.json" python3 -c "import json,os; print(json.load(open(os.environ['WEBHOOK_CONFIG_FILE']))['enabled'])")
  if [[ "$DISABLED" == "False" ]]; then
    pass
  else
    fail "expected disabled after disable command"
  fi
else
  fail "expected enabled after enable command"
fi
teardown_test_home

# --- Test: webhook-setup.sh remove ---
begin_test "webhook: setup remove deletes config"
setup_test_home
mkdir -p "$HOME/.claude/supercharger"
echo '{"platform":"slack","url":"https://example.com","enabled":true}' > "$HOME/.claude/supercharger/webhook.json"

bash "$REPO_DIR/tools/webhook-setup.sh" remove >/dev/null 2>&1

assert_file_not_exists "$HOME/.claude/supercharger/webhook.json" && pass
teardown_test_home

# --- Test: session-complete hook exits 0 with no webhook ---
begin_test "webhook: session-complete hook exits clean with no webhook"
setup_test_home
mkdir -p "$HOME/.claude/supercharger"

echo "" | bash "$REPO_DIR/hooks/session-complete.sh" >/dev/null 2>&1
EXIT_CODE=$?
if [ "$EXIT_CODE" -eq 0 ]; then
  pass
else
  fail "expected exit code 0, got $EXIT_CODE"
fi
teardown_test_home

# --- Test: session-complete hook creates .last-session marker ---
begin_test "webhook: session-complete creates .last-session marker"
setup_test_home
mkdir -p "$HOME/.claude/supercharger/summaries"

echo "" | bash "$REPO_DIR/hooks/session-complete.sh" >/dev/null 2>&1

assert_file_exists "$HOME/.claude/supercharger/summaries/.last-session" && pass
teardown_test_home

# --- Test: notify hook still works without webhook ---
begin_test "webhook: notify hook works without webhook config"
setup_test_home
mkdir -p "$HOME/.claude/supercharger"

echo "" | bash "$REPO_DIR/hooks/notify.sh" >/dev/null 2>&1
EXIT_CODE=$?
if [ "$EXIT_CODE" -eq 0 ]; then
  pass
else
  fail "expected exit code 0, got $EXIT_CODE"
fi
teardown_test_home

# --- Test: session-complete hook registered in full mode ---
begin_test "webhook: session-complete hook in full mode hook list"
source "$REPO_DIR/lib/hooks.sh"

HOOKS=$(get_hooks_for_mode "full" "false" "/tmp/hooks")
echo "$HOOKS" | grep -q "session-complete.sh" && pass || fail "expected session-complete.sh in full mode hooks"

report
