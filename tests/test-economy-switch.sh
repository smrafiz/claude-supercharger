#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

TOOL="$REPO_DIR/tools/economy-switch.sh"

# Seed helper: set up a minimal installed environment with economy files
seed_economy_env() {
  mkdir -p "$HOME/.claude/rules"
  mkdir -p "$HOME/.claude/supercharger/economy"
  cp "$REPO_DIR/configs/economy/standard.md" "$HOME/.claude/supercharger/economy/standard.md"
  cp "$REPO_DIR/configs/economy/lean.md"     "$HOME/.claude/supercharger/economy/lean.md"
  cp "$REPO_DIR/configs/economy/minimal.md"  "$HOME/.claude/supercharger/economy/minimal.md"
  # Deploy a base economy.md with an active tier block
  sed -e "s/{{ACTIVE_TIER}}/$(cat "$REPO_DIR/configs/economy/lean.md")/" \
    "$REPO_DIR/configs/universal/economy.md" > "$HOME/.claude/rules/economy.md" 2>/dev/null || \
    cp "$REPO_DIR/configs/economy/lean.md" "$HOME/.claude/rules/economy.md"
}

# Test 1: Invalid tier → exit 1
begin_test "economy-switch: invalid tier exits 1"
setup_test_home
seed_economy_env
bash "$TOOL" turbo >/dev/null 2>&1
EXIT_CODE=$?
if [ $EXIT_CODE -eq 1 ]; then pass
else fail "expected exit 1, got $EXIT_CODE"; fi
teardown_test_home

# Test 2: Invalid tier → error message contains tier name
begin_test "economy-switch: invalid tier prints error"
setup_test_home
seed_economy_env
OUTPUT=$(bash "$TOOL" turbo 2>&1 || true)
if printf '%s\n' "$OUTPUT" | grep -qi "unknown\|invalid\|turbo"; then pass
else fail "expected error message, got: $OUTPUT"; fi
teardown_test_home

# Test 3: Valid tier → economy.md updated
begin_test "economy-switch: valid tier updates economy.md"
setup_test_home
seed_economy_env
bash "$TOOL" minimal >/dev/null 2>&1 || true
if assert_file_contains "$HOME/.claude/rules/economy.md" "Minimal"; then pass; fi
teardown_test_home

# Test 4: No args → exits 0 (shows usage)
begin_test "economy-switch: no args shows usage and exits 0"
setup_test_home
seed_economy_env
bash "$TOOL" >/dev/null 2>&1
EXIT_CODE=$?
if [ $EXIT_CODE -eq 0 ]; then pass
else fail "expected exit 0, got $EXIT_CODE"; fi
teardown_test_home

# Test 5: Missing economy.md → exits 1
begin_test "economy-switch: missing economy.md exits 1"
setup_test_home
mkdir -p "$HOME/.claude/supercharger/economy"
cp "$REPO_DIR/configs/economy/lean.md" "$HOME/.claude/supercharger/economy/lean.md"
bash "$TOOL" lean >/dev/null 2>&1
EXIT_CODE=$?
if [ $EXIT_CODE -eq 1 ]; then pass
else fail "expected exit 1 (no economy.md), got $EXIT_CODE"; fi
teardown_test_home

report
