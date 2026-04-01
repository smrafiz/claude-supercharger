#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

source "$REPO_DIR/lib/utils.sh"
source "$REPO_DIR/lib/roles.sh"
source "$REPO_DIR/lib/economy.sh"

# --- Test: developer role has economy metadata ---
begin_test "economy: developer role contains economy metadata"
assert_file_contains "$REPO_DIR/configs/roles/developer.md" "Default economy: Lean" &&
assert_file_contains "$REPO_DIR/configs/roles/developer.md" "Economy range: unrestricted" &&
pass

# --- Test: student role has correct constraints ---
begin_test "economy: student role has Standard floor and Lean ceiling"
assert_file_contains "$REPO_DIR/configs/roles/student.md" "Default economy: Standard" &&
assert_file_contains "$REPO_DIR/configs/roles/student.md" "Economy range: Standard–Lean" &&
pass

# --- Test: writer role has correct constraints ---
begin_test "economy: writer role has Standard floor"
assert_file_contains "$REPO_DIR/configs/roles/writer.md" "Default economy: Standard" &&
assert_file_contains "$REPO_DIR/configs/roles/writer.md" "Economy range: Standard–unrestricted" &&
pass

# --- Test: data role has economy metadata ---
begin_test "economy: data role has economy metadata"
assert_file_contains "$REPO_DIR/configs/roles/data.md" "Default economy: Lean" &&
assert_file_contains "$REPO_DIR/configs/roles/data.md" "Economy range: unrestricted" &&
pass

# --- Test: pm role has economy metadata ---
begin_test "economy: pm role has economy metadata"
assert_file_contains "$REPO_DIR/configs/roles/pm.md" "Default economy: Lean" &&
assert_file_contains "$REPO_DIR/configs/roles/pm.md" "Economy range: unrestricted" &&
pass

# --- Test: economy.md deployed with active tier ---
begin_test "economy: deploy_economy creates economy.md with active tier"
setup_test_home
mkdir -p "$HOME/.claude/rules"
mkdir -p "$HOME/.claude/supercharger/economy"

SELECTED_TIER="lean"
deploy_economy "$REPO_DIR" "$SELECTED_TIER"

assert_file_exists "$HOME/.claude/rules/economy.md" &&
assert_file_contains "$HOME/.claude/rules/economy.md" "Active Tier: Lean" &&
assert_file_contains "$HOME/.claude/rules/economy.md" "Universal Output Rules" &&
assert_file_not_contains "$HOME/.claude/rules/economy.md" "{{ACTIVE_TIER}}" &&
pass
teardown_test_home

# --- Test: all tier templates deployed to supercharger/economy/ ---
begin_test "economy: all 3 tier templates in supercharger/economy/"
setup_test_home
mkdir -p "$HOME/.claude/rules"
mkdir -p "$HOME/.claude/supercharger/economy"

deploy_economy "$REPO_DIR" "lean"

assert_file_exists "$HOME/.claude/supercharger/economy/standard.md" &&
assert_file_exists "$HOME/.claude/supercharger/economy/lean.md" &&
assert_file_exists "$HOME/.claude/supercharger/economy/minimal.md" &&
pass
teardown_test_home

# --- Test: standard tier content is correct ---
begin_test "economy: standard tier has correct content"
setup_test_home
mkdir -p "$HOME/.claude/rules"
mkdir -p "$HOME/.claude/supercharger/economy"

deploy_economy "$REPO_DIR" "standard"

assert_file_contains "$HOME/.claude/rules/economy.md" "Active Tier: Standard" &&
assert_file_contains "$HOME/.claude/rules/economy.md" "Clear paragraphs, max 3 per response" &&
pass
teardown_test_home

# --- Test: minimal tier content is correct ---
begin_test "economy: minimal tier has correct content"
setup_test_home
mkdir -p "$HOME/.claude/rules"
mkdir -p "$HOME/.claude/supercharger/economy"

deploy_economy "$REPO_DIR" "minimal"

assert_file_contains "$HOME/.claude/rules/economy.md" "Active Tier: Minimal" &&
assert_file_contains "$HOME/.claude/rules/economy.md" "Telegraphic" &&
pass
teardown_test_home

# --- Test: tier validation — student blocks minimal ---
begin_test "economy: student role blocks minimal → corrects to lean"
setup_test_home

RESULT=$(validate_tier_for_roles "minimal" "student" 2>/dev/null)
if [[ "$RESULT" == "lean" ]]; then
  pass
else
  fail "expected 'lean', got '$RESULT'"
fi
teardown_test_home

# --- Test: tier validation — developer allows minimal ---
begin_test "economy: developer role allows minimal"
setup_test_home

RESULT=$(validate_tier_for_roles "minimal" "developer" 2>/dev/null)
if [[ "$RESULT" == "minimal" ]]; then
  pass
else
  fail "expected 'minimal', got '$RESULT'"
fi
teardown_test_home

# --- Test: tier validation — writer blocks minimal, allows lean ---
begin_test "economy: writer allows lean (no ceiling)"
setup_test_home

RESULT=$(validate_tier_for_roles "lean" "writer" 2>/dev/null)
if [[ "$RESULT" == "lean" ]]; then
  pass
else
  fail "expected 'lean', got '$RESULT'"
fi
teardown_test_home

# --- Test: multi-role floor — developer+student → standard floor ---
begin_test "economy: developer+student multi-role → minimal blocked"
setup_test_home

RESULT=$(validate_tier_for_roles "minimal" "developer,student" 2>/dev/null)
if [[ "$RESULT" == "lean" ]]; then
  pass
else
  fail "expected 'lean', got '$RESULT'"
fi
teardown_test_home

# --- Test: get_default_tier_for_roles ---
begin_test "economy: default tier for developer is lean"
RESULT=$(get_default_tier_for_roles "developer")
if [[ "$RESULT" == "lean" ]]; then
  pass
else
  fail "expected 'lean', got '$RESULT'"
fi

begin_test "economy: default tier for student is standard"
RESULT=$(get_default_tier_for_roles "student")
if [[ "$RESULT" == "standard" ]]; then
  pass
else
  fail "expected 'standard', got '$RESULT'"
fi

begin_test "economy: default tier for developer,student is standard (most restrictive)"
RESULT=$(get_default_tier_for_roles "developer,student")
if [[ "$RESULT" == "standard" ]]; then
  pass
else
  fail "expected 'standard', got '$RESULT'"
fi

# --- Test: full install includes economy.md ---
begin_test "economy: full non-interactive install deploys economy.md"
setup_test_home

bash "$REPO_DIR/install.sh" --mode standard --roles developer --economy lean --config deploy --settings deploy >/dev/null 2>&1

assert_file_exists "$HOME/.claude/rules/economy.md" &&
assert_file_contains "$HOME/.claude/rules/economy.md" "Active Tier: Lean" &&
assert_file_exists "$HOME/.claude/supercharger/economy/standard.md" &&
assert_file_exists "$HOME/.claude/supercharger/economy/lean.md" &&
assert_file_exists "$HOME/.claude/supercharger/economy/minimal.md" &&
pass
teardown_test_home

# --- Test: install with student + minimal → auto-corrects ---
begin_test "economy: install student+minimal auto-corrects to lean"
setup_test_home

bash "$REPO_DIR/install.sh" --mode safe --roles student --economy minimal --config deploy --settings deploy >/dev/null 2>&1

assert_file_exists "$HOME/.claude/rules/economy.md" &&
assert_file_contains "$HOME/.claude/rules/economy.md" "Active Tier: Lean" &&
pass
teardown_test_home

# --- Test: economy-switch.sh switches tier ---
begin_test "economy: economy-switch.sh switches lean to standard"
setup_test_home
mkdir -p "$HOME/.claude/rules"
mkdir -p "$HOME/.claude/supercharger/economy"

deploy_economy "$REPO_DIR" "lean"

bash "$REPO_DIR/tools/economy-switch.sh" standard >/dev/null 2>&1

assert_file_contains "$HOME/.claude/rules/economy.md" "Active Tier: Standard" &&
assert_file_not_contains "$HOME/.claude/rules/economy.md" "Active Tier: Lean" &&
pass
teardown_test_home

# --- Test: economy-switch.sh validates against roles ---
begin_test "economy: economy-switch.sh respects student ceiling"
setup_test_home
mkdir -p "$HOME/.claude/rules"
mkdir -p "$HOME/.claude/supercharger/economy"

deploy_economy "$REPO_DIR" "lean"
# Deploy student role to rules/ so switch tool detects it
cp "$REPO_DIR/configs/roles/student.md" "$HOME/.claude/rules/student.md"

bash "$REPO_DIR/tools/economy-switch.sh" minimal >/dev/null 2>&1

assert_file_contains "$HOME/.claude/rules/economy.md" "Active Tier: Lean" &&
pass
teardown_test_home

# --- Test: economy-switch.sh rejects invalid tier ---
begin_test "economy: economy-switch.sh rejects invalid tier name"
setup_test_home
mkdir -p "$HOME/.claude/rules"
mkdir -p "$HOME/.claude/supercharger/economy"

deploy_economy "$REPO_DIR" "lean"

bash "$REPO_DIR/tools/economy-switch.sh" turbo >/dev/null 2>&1
EXIT_CODE=$?

if [ "$EXIT_CODE" -ne 0 ]; then
  pass
else
  fail "expected non-zero exit code for invalid tier"
fi
teardown_test_home

report
