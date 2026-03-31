#!/usr/bin/env bash
# Claude Supercharger — Test Helpers

TESTS_PASSED=0
TESTS_FAILED=0
CURRENT_TEST=""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

setup_test_home() {
  TEST_HOME=$(mktemp -d)
  export HOME="$TEST_HOME"
  mkdir -p "$HOME/.claude"
}

teardown_test_home() {
  if [ -n "$TEST_HOME" ] && [ -d "$TEST_HOME" ]; then
    rm -rf "$TEST_HOME"
  fi
}

begin_test() {
  CURRENT_TEST="$1"
}

pass() {
  TESTS_PASSED=$((TESTS_PASSED + 1))
  echo -e "  ${GREEN}PASS${NC} $CURRENT_TEST"
}

fail() {
  local reason="${1:-}"
  TESTS_FAILED=$((TESTS_FAILED + 1))
  echo -e "  ${RED}FAIL${NC} $CURRENT_TEST${reason:+ — $reason}"
}

assert_file_exists() {
  local path="$1"
  if [ -f "$path" ]; then
    return 0
  else
    fail "expected file to exist: $path"
    return 1
  fi
}

assert_file_not_exists() {
  local path="$1"
  if [ ! -f "$path" ]; then
    return 0
  else
    fail "expected file to NOT exist: $path"
    return 1
  fi
}

assert_dir_exists() {
  local path="$1"
  if [ -d "$path" ]; then
    return 0
  else
    fail "expected directory to exist: $path"
    return 1
  fi
}

assert_file_contains() {
  local path="$1"
  local pattern="$2"
  if grep -q "$pattern" "$path" 2>/dev/null; then
    return 0
  else
    fail "expected '$path' to contain '$pattern'"
    return 1
  fi
}

assert_file_not_contains() {
  local path="$1"
  local pattern="$2"
  if ! grep -q "$pattern" "$path" 2>/dev/null; then
    return 0
  else
    fail "expected '$path' to NOT contain '$pattern'"
    return 1
  fi
}

assert_exit_code() {
  local expected="$1"
  local actual="$2"
  if [ "$actual" -eq "$expected" ]; then
    return 0
  else
    fail "expected exit code $expected, got $actual"
    return 1
  fi
}

# Pipe JSON hook input to a hook script, capture exit code
run_hook() {
  local hook_script="$1"
  local command="$2"
  local escaped_command
  escaped_command=$(echo "$command" | sed 's/\\/\\\\/g')
  local json_input="{\"input\":{\"command\":\"$escaped_command\"}}"
  echo "$json_input" | bash "$hook_script" >/dev/null 2>&1
  return $?
}

report() {
  local total=$((TESTS_PASSED + TESTS_FAILED))
  echo ""
  echo -e "${GREEN}$TESTS_PASSED passed${NC}, ${RED}$TESTS_FAILED failed${NC} ($total total)"
  return $TESTS_FAILED
}
