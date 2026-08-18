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

# --- configuration isolation -------------------------------------------------
# v2.26.46: clear ambient SUPERCHARGER_* settings before any test runs.
#
# These variables are the documented way to disable a guard, so a developer who
# turns one off in ~/.claude/settings.json (an `env` block reaches hooks AND the
# shell running the suite) silently disables it for the tests too. The hook then
# exits at its first line and every assertion about it fails — while CI, with a
# clean environment, stays green.
#
# That happened: SUPERCHARGER_MCP_BREAKER=0 was set as a workaround for a real
# bug, and the resulting 3 failures read as a regression in unrelated work. Time
# went into bisecting code that was never broken.
#
# Two are preserved deliberately: NO_NOTIFY is set by run.sh so the suite does not
# fire desktop notifications, and TEST_HOME is this file's own isolation flag.
# Everything else is cleared here, BEFORE tests do their own inline or exported
# assignments — those still work, because they happen after this point.
for _sc_v in $(env | sed -n 's/^\(SUPERCHARGER_[A-Za-z0-9_]*\)=.*/\1/p'); do
  case "$_sc_v" in
    SUPERCHARGER_NO_NOTIFY|SUPERCHARGER_TEST_HOME) continue ;;
  esac
  unset "$_sc_v"
done
unset _sc_v

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

# Windows python defaults stdout AND file writes to the ANSI codepage (cp1252).
# Tests build fixtures containing characters it cannot encode — the zero-width
# steganography decoy in test-agent-poisoning is U+200B — so `open(f,'w').write()`
# raised UnicodeEncodeError, the fixture was never created, and the scanner
# correctly found nothing in a file that did not exist. The failure read as
# "zero-width not detected", pointing at the scanner rather than at the harness.
#
# Set here because helpers.sh is the one file every test sources, the same reason
# hooks get it from lib-paths.sh. `:=` honours an explicit setting.
: "${PYTHONIOENCODING:=utf-8}"
: "${PYTHONUTF8:=1}"
export PYTHONIOENCODING PYTHONUTF8

# The per-project scope key, derived the way the READERS derive it (python).
#
# Tests kept their own copies of this — four of them, already diverged: some
# folded '\' and ':' as sc_project_key does, some did not, so one expected a
# filename with a drive colon in it that no writer ever produces.
#
# The path goes in on STDIN. Passed as argv or in an env var, MSYS respells it in
# transit on Git Bash, so '/Users/me/proj' arrived as
# 'C:/Program Files/Git/Users/me/proj' and the test reported a channel
# disagreement it had manufactured itself. Neither stdin nor `-c` text is
# converted.
sc_key_for() { # project dir -> the key sc_project_key()/_project_key() produce
  printf '%s\n' "$1" | python3 -c "
import sys
k = sys.stdin.readline().rstrip('\r\n')
k = k.replace('/', '-').replace('\\\\', '-').replace(':', '-')
k = k[1:] if k.startswith('-') else k
k = k[-100:] if len(k) > 100 else k
print(k or 'root')"
}

# Put real tools on a synthetic PATH, for tests that need a tool to be ABSENT.
#
# Shims, not symlinks. `ln -s` on Git Bash needs developer mode or admin rights
# and degrades SILENTLY without them: $dir ends up empty, every command in it is
# missing, and the test reports whatever the code under test does with no tools
# at all. That reads as a product bug — test-lib-hash spent a recon cycle looking
# like a broken sc_md5 when the harness had simply failed to build its sandbox.
#
# The shebang is an absolute /bin/sh because callers replace PATH with $dir; a
# `#!/usr/bin/env bash` shim named bash would re-enter itself.
#
# Returns 1 (and says so) when the sandbox cannot be built, so a harness failure
# never again masquerades as a behaviour failure.
shim_tools() { # <dir> <tool>...
  local dir="$1"; shift
  local t src
  mkdir -p "$dir" || return 1
  for t in "$@"; do
    src=$(command -v "$t" 2>/dev/null) || continue
    [ -n "$src" ] || continue
    printf '#!/bin/sh\nexec "%s" "$@"\n' "$src" > "$dir/$t" && chmod +x "$dir/$t"
  done
  # Prove the sandbox actually executes something, rather than assuming it did.
  for t in "$@"; do
    [ -x "$dir/$t" ] || continue
    "$dir/$t" </dev/null >/dev/null 2>&1
    # Any exit status means it RAN; 126/127 mean it could not be executed.
    case $? in 126|127) ;; *) return 0 ;; esac
  done
  echo "HARNESS-BROKEN: no runnable shim in $dir (symlink/exec unavailable?)" >&2
  return 1
}

report() {
  local total=$((TESTS_PASSED + TESTS_FAILED))
  echo ""
  echo -e "${GREEN}$TESTS_PASSED passed${NC}, ${RED}$TESTS_FAILED failed${NC} ($total total)"
  return $TESTS_FAILED
}

# v2.27.36: return a path that NATIVE Windows tools can resolve.
#
# Claude Code launches hooks through Git Bash, and MSYS rewrites paths passed as
# ENV VARS in transit — but not string content inside a JSON payload. So a test
# that puts `mktemp -d` into a payload's `cwd` field hands native Windows python
# an MSYS virtual path like /tmp/tmp.XXXX, which it cannot resolve: the scanner
# finds nothing and reports clean. The same directory passed via HOME works,
# because that one IS converted — which is why two tests using the identical
# mktemp call disagreed on Windows, and why it looked like a product bug for two
# releases. cygpath is the documented MSYS conversion tool and ships with Git for
# Windows; off Windows this is a no-op passthrough.
native_path() {
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -m "$1" 2>/dev/null || printf '%s' "$1"
  else
    printf '%s' "$1"
  fi
}
