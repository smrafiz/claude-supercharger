#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

TOOL="$REPO_DIR/tools/hook-toggle.sh"

# Seed helper: create settings.json with a supercharger hook entry
seed_settings() {
  mkdir -p "$HOME/.claude"
  cat > "$HOME/.claude/settings.json" <<'EOF'
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "/home/.claude/supercharger/hooks/prompt-validator.sh #supercharger"
          }
        ]
      }
    ]
  }
}
EOF
}

# Test 1: Toggle off → command prefixed with "# "
begin_test "hook-toggle: toggle off disables hook"
setup_test_home
seed_settings
bash "$TOOL" prompt-validator off >/dev/null 2>&1
if assert_file_contains "$HOME/.claude/settings.json" '"# '; then pass; fi
teardown_test_home

# Test 2: Toggle on → prefix removed
begin_test "hook-toggle: toggle on re-enables hook"
setup_test_home
seed_settings
bash "$TOOL" prompt-validator off >/dev/null 2>&1
bash "$TOOL" prompt-validator on  >/dev/null 2>&1
assert_file_not_contains "$HOME/.claude/settings.json" '"# ' && pass
teardown_test_home

# Test 3: Unknown hook → exit 1
begin_test "hook-toggle: unknown hook exits 1"
setup_test_home
seed_settings
bash "$TOOL" nonexistent-hook off >/dev/null 2>&1
EXIT_CODE=$?
if [ $EXIT_CODE -eq 1 ]; then pass
else fail "expected exit 1 for unknown hook, got $EXIT_CODE"; fi
teardown_test_home

# Test 4: Toggle off already-disabled → exit 0, no double-prefix
begin_test "hook-toggle: toggle off twice does not double-prefix"
setup_test_home
seed_settings
bash "$TOOL" prompt-validator off >/dev/null 2>&1
bash "$TOOL" prompt-validator off >/dev/null 2>&1
EXIT_CODE=$?
OUTPUT=$(grep '"# ' "$HOME/.claude/settings.json" | wc -l | tr -d ' ')
if [ $EXIT_CODE -eq 0 ] && [ "$OUTPUT" -eq 1 ]; then pass
else fail "expected single prefix and exit 0, got exit=$EXIT_CODE prefix_count=$OUTPUT"; fi
teardown_test_home

# Test 5: No settings.json → exit 1
begin_test "hook-toggle: missing settings.json exits 1"
setup_test_home
bash "$TOOL" prompt-validator off >/dev/null 2>&1
EXIT_CODE=$?
if [ $EXIT_CODE -eq 1 ]; then pass
else fail "expected exit 1 (no settings.json), got $EXIT_CODE"; fi
teardown_test_home

report
