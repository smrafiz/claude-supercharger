#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
HOOK="$REPO_DIR/hooks/adaptive-economy.sh"

echo "=== Adaptive Economy v2 Tests ==="

_make_input() {
  local pct="$1"
  printf '{"cwd":"%s","context_window":{"used_percentage":%s}}' "$SCOPE_DIR" "$pct"
}

# --- Test 1: auto-switches to lean at 70% when standard ---
begin_test "adaptive-economy-v2: auto-switches to lean at 70% when standard"
setup_test_home
SCOPE_DIR="$HOME/.claude/supercharger/scope"
mkdir -p "$SCOPE_DIR"
echo "standard" > "$SCOPE_DIR/.economy-tier"
rm -f "$SCOPE_DIR/.eco-last"

_make_input 72 | bash "$HOOK" >/dev/null 2>&1

RESULT=$(cat "$SCOPE_DIR/.economy-tier" 2>/dev/null | tr -d '[:space:]')
if [ "$RESULT" = "lean" ]; then
  pass
else
  fail "expected 'lean', got '$RESULT'"
fi
teardown_test_home

# --- Test 2: auto-switches to minimal at 80% when lean ---
begin_test "adaptive-economy-v2: auto-switches to minimal at 80% when lean"
setup_test_home
SCOPE_DIR="$HOME/.claude/supercharger/scope"
mkdir -p "$SCOPE_DIR"
echo "lean" > "$SCOPE_DIR/.economy-tier"
rm -f "$SCOPE_DIR/.eco-last"

_make_input 82 | bash "$HOOK" >/dev/null 2>&1

RESULT=$(cat "$SCOPE_DIR/.economy-tier" 2>/dev/null | tr -d '[:space:]')
if [ "$RESULT" = "minimal" ]; then
  pass
else
  fail "expected 'minimal', got '$RESULT'"
fi
teardown_test_home

# --- Test 3: suggests (not auto) revert at <30% minimal ---
begin_test "adaptive-economy-v2: suggests (not auto) revert at <30% minimal"
setup_test_home
SCOPE_DIR="$HOME/.claude/supercharger/scope"
mkdir -p "$SCOPE_DIR"
echo "minimal" > "$SCOPE_DIR/.economy-tier"
rm -f "$SCOPE_DIR/.eco-last"

OUTPUT=$(_make_input 20 | bash "$HOOK" 2>/dev/null)

# Tier must remain minimal
RESULT=$(cat "$SCOPE_DIR/.economy-tier" 2>/dev/null | tr -d '[:space:]')
if [ "$RESULT" != "minimal" ]; then
  fail "tier changed from minimal (got '$RESULT')"
elif echo "$OUTPUT" | grep -q "ECO"; then
  pass
else
  fail "expected ECO in output, got: $OUTPUT"
fi
teardown_test_home

# --- Test 4: respects opt-out env var ---
begin_test "adaptive-economy-v2: respects SUPERCHARGER_NO_AUTO_ECONOMY=1"
setup_test_home
SCOPE_DIR="$HOME/.claude/supercharger/scope"
mkdir -p "$SCOPE_DIR"
echo "standard" > "$SCOPE_DIR/.economy-tier"
rm -f "$SCOPE_DIR/.eco-last"

export SUPERCHARGER_NO_AUTO_ECONOMY=1
_make_input 75 | bash "$HOOK" >/dev/null 2>&1
unset SUPERCHARGER_NO_AUTO_ECONOMY

RESULT=$(cat "$SCOPE_DIR/.economy-tier" 2>/dev/null | tr -d '[:space:]')
if [ "$RESULT" = "standard" ]; then
  pass
else
  fail "expected 'standard' (unchanged), got '$RESULT'"
fi
teardown_test_home

report
