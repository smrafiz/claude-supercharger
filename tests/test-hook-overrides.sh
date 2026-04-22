#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

HOOKS_DIR="$REPO_DIR/hooks"
LIB="$HOOKS_DIR/lib-suppress.sh"
PROJECT_CONFIG="$HOOKS_DIR/project-config.sh"

echo "=== Hook Overrides Tests ==="

# ── Test 1: disabled-hooks file created from config ───────────────────────────
begin_test "hook overrides: disabled-hooks file created from config"
result=$(
  setup_test_home
  mkdir -p "$HOME/.claude/supercharger/scope"
  PROJ=$(mktemp -d)
  cat > "$PROJ/.supercharger.json" <<'JSON'
{"roles": ["developer"], "economy": "lean", "disableHooks": ["typecheck", "quality-gate"]}
JSON
  INPUT=$(python3 -c "import json; print(json.dumps({'cwd': '$PROJ'}))")
  printf '%s\n' "$INPUT" | bash "$PROJECT_CONFIG" >/dev/null 2>&1 || true
  DISABLED_FILE="$HOME/.claude/supercharger/scope/.disabled-hooks"
  if [ -f "$DISABLED_FILE" ] && grep -qx "typecheck" "$DISABLED_FILE" && grep -qx "quality-gate" "$DISABLED_FILE"; then
    echo "ok"
  fi
  rm -rf "$PROJ"
  teardown_test_home
)
if [ "$result" = "ok" ]; then
  pass
else
  fail "disabled-hooks file not created or missing expected entries"
fi

# ── Test 2: check_hook_disabled returns 0 for disabled hook ───────────────────
begin_test "hook overrides: check_hook_disabled returns 0 for disabled hook"
result=$(
  setup_test_home
  mkdir -p "$HOME/.claude/supercharger/scope"
  printf 'typecheck\n' > "$HOME/.claude/supercharger/scope/.disabled-hooks"
  (
    source "$LIB"
    check_hook_disabled "typecheck"
  )
  echo $?
  teardown_test_home
)
if [ "$result" = "0" ]; then
  pass
else
  fail "expected exit 0 for disabled hook, got $result"
fi

# ── Test 3: check_hook_disabled returns 1 for enabled hook ────────────────────
begin_test "hook overrides: check_hook_disabled returns 1 for enabled hook"
result=$(
  setup_test_home
  mkdir -p "$HOME/.claude/supercharger/scope"
  printf 'typecheck\n' > "$HOME/.claude/supercharger/scope/.disabled-hooks"
  (
    source "$LIB"
    check_hook_disabled "safety"
  )
  echo $?
  teardown_test_home
)
if [ "$result" = "1" ]; then
  pass
else
  fail "expected exit 1 for enabled hook, got $result"
fi

# ── Test 4: cleared when disableHooks removed from config ─────────────────────
begin_test "hook overrides: cleared when disableHooks removed from config"
result=$(
  setup_test_home
  mkdir -p "$HOME/.claude/supercharger/scope"
  printf 'typecheck\n' > "$HOME/.claude/supercharger/scope/.disabled-hooks"
  PROJ=$(mktemp -d)
  cat > "$PROJ/.supercharger.json" <<'JSON'
{"roles": ["developer"]}
JSON
  INPUT=$(python3 -c "import json; print(json.dumps({'cwd': '$PROJ'}))")
  printf '%s\n' "$INPUT" | bash "$PROJECT_CONFIG" >/dev/null 2>&1 || true
  DISABLED_FILE="$HOME/.claude/supercharger/scope/.disabled-hooks"
  if [ ! -f "$DISABLED_FILE" ]; then
    echo "ok"
  fi
  rm -rf "$PROJ"
  teardown_test_home
)
if [ "$result" = "ok" ]; then
  pass
else
  fail "expected .disabled-hooks to be removed when disableHooks not in config"
fi

report
