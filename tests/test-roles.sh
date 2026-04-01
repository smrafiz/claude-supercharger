#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

source "$REPO_DIR/lib/utils.sh"
source "$REPO_DIR/lib/roles.sh"

# --- Test: single role selected ---
begin_test "roles: single role → only that role in rules/"
setup_test_home
mkdir -p "$HOME/.claude/rules"
mkdir -p "$HOME/.claude/supercharger/roles"

SELECTED_ROLES=("developer")
deploy_roles "$REPO_DIR"

assert_file_exists "$HOME/.claude/rules/developer.md" &&
assert_file_not_exists "$HOME/.claude/rules/writer.md" &&
assert_file_not_exists "$HOME/.claude/rules/student.md" &&
assert_file_not_exists "$HOME/.claude/rules/data.md" &&
assert_file_not_exists "$HOME/.claude/rules/pm.md" &&
pass
teardown_test_home

# --- Test: multiple roles selected ---
begin_test "roles: multiple roles → selected in rules/"
setup_test_home
mkdir -p "$HOME/.claude/rules"
mkdir -p "$HOME/.claude/supercharger/roles"

SELECTED_ROLES=("developer" "pm")
deploy_roles "$REPO_DIR"

assert_file_exists "$HOME/.claude/rules/developer.md" &&
assert_file_exists "$HOME/.claude/rules/pm.md" &&
assert_file_not_exists "$HOME/.claude/rules/writer.md" &&
assert_file_not_exists "$HOME/.claude/rules/student.md" &&
assert_file_not_exists "$HOME/.claude/rules/data.md" &&
pass
teardown_test_home

# --- Test: all roles available in supercharger/roles/ ---
begin_test "roles: all 8 roles in supercharger/roles/ for mode switching"
setup_test_home
mkdir -p "$HOME/.claude/rules"
mkdir -p "$HOME/.claude/supercharger/roles"

SELECTED_ROLES=("developer")
deploy_roles "$REPO_DIR"

assert_file_exists "$HOME/.claude/supercharger/roles/developer.md" &&
assert_file_exists "$HOME/.claude/supercharger/roles/writer.md" &&
assert_file_exists "$HOME/.claude/supercharger/roles/student.md" &&
assert_file_exists "$HOME/.claude/supercharger/roles/data.md" &&
assert_file_exists "$HOME/.claude/supercharger/roles/pm.md" &&
assert_file_exists "$HOME/.claude/supercharger/roles/designer.md" &&
assert_file_exists "$HOME/.claude/supercharger/roles/devops.md" &&
assert_file_exists "$HOME/.claude/supercharger/roles/researcher.md" &&
pass
teardown_test_home

# --- Test: new role selected ---
begin_test "roles: designer role deploys to rules/"
setup_test_home
mkdir -p "$HOME/.claude/rules"
mkdir -p "$HOME/.claude/supercharger/roles"

SELECTED_ROLES=("designer")
deploy_roles "$REPO_DIR"

assert_file_exists "$HOME/.claude/rules/designer.md" &&
assert_file_not_exists "$HOME/.claude/rules/developer.md" &&
pass
teardown_test_home

report
