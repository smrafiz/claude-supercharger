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

report
