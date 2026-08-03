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

# --- writable-state isolation ------------------------------------------------
# Hooks write telemetry under HOME — the block ledger, the audit log, scope
# flags. tests/run.sh already gives every file its own HOME (see run_one), so the
# SUITE has always been isolated. What was NOT covered is running a single file
# directly — `bash tests/test-foo.sh` — which inherits the developer's real HOME
# and appends test payloads to live telemetry. That is the ordinary way to work
# on one test, so it is the path that actually leaks.
#
# Isolation is by moving HOME, NOT by exporting SUPERCHARGER_STATE, matching
# run_one. The tests read state back through "$HOME/.claude/supercharger/..."
# literals while hooks resolve it via lib-paths.sh; overriding only STATE splits
# those apart — the hook writes one place, the assertion looks in another — which
# failed 151 assertions when tried here.
#
# Tests that set their own HOME afterwards are unaffected: state follows whatever
# HOME is current when the hook runs.
if [ -z "${SUPERCHARGER_TEST_HOME:-}" ]; then
  SUPERCHARGER_TEST_HOME="${TMPDIR:-/tmp}/sc-test-home-$$"
  mkdir -p "$SUPERCHARGER_TEST_HOME/.claude/supercharger/scope" \
           "$SUPERCHARGER_TEST_HOME/.claude/supercharger/audit" 2>/dev/null || true
  # Canonicalise, for the reason run_one documents: on macOS TMPDIR lives under
  # /var/folders/... and /var is a symlink to /private/var. path-guard realpaths
  # paths, so a symlinked HOME trips its in-path-symlink check and wrongly denies
  # writes the tests expect to succeed.
  SUPERCHARGER_TEST_HOME=$(cd "$SUPERCHARGER_TEST_HOME" && pwd -P)
  export SUPERCHARGER_TEST_HOME
  export HOME="$SUPERCHARGER_TEST_HOME"
  # Best-effort: several tests install their own EXIT trap, which replaces this
  # one. tests/run.sh sweeps leftovers by pattern for that reason.
  trap 'rm -rf "${SUPERCHARGER_TEST_HOME:-/nonexistent}" 2>/dev/null || true' EXIT
fi

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
  escaped_command=$(printf '%s' "$command" | python3 -c "import sys,json; s=sys.stdin.read(); print(json.dumps(s)[1:-1])" 2>/dev/null || printf '%s' "$command" | sed 's/\\/\\\\/g; s/"/\\"/g')
  local json_input="{\"tool_input\":{\"command\":\"$escaped_command\"}}"
  echo "$json_input" | bash "$hook_script" >/dev/null 2>&1
  return $?
}

report() {
  local total=$((TESTS_PASSED + TESTS_FAILED))
  echo ""
  echo -e "${GREEN}$TESTS_PASSED passed${NC}, ${RED}$TESTS_FAILED failed${NC} ($total total)"
  return $TESTS_FAILED
}
