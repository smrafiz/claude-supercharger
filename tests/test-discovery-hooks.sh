#!/usr/bin/env bash
# Tests for the v2.5/v2.6 discovery hooks.
# Each hook captures payload schema for a Claude Code event whose tool_input
# shape isn't fully documented. Shared properties verified here:
#   1. hook exists and is executable
#   2. fires without error and writes a JSONL line to its audit file
#   3. respects its SUPERCHARGER_*_DISCOVERY=0 disable env var
#   4. survives malformed JSON input without crashing the chain
# Elicitation gets one extra test: response values must not appear in the log.

REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

echo "=== discovery-hooks Tests ==="

setup_test_home

AUDIT_DIR="$HOME/.claude/supercharger/audit"

# (hook_basename, audit_filename, disable_env_var, sample_payload)
run_basic_suite() {
  local hook_name="$1"
  local audit_file="$2"
  local disable_var="$3"
  local payload="$4"

  local hook_path="$REPO_DIR/hooks/${hook_name}.sh"

  begin_test "$hook_name: hook exists and is executable"
  [ -x "$hook_path" ] && pass || fail "missing or not executable: $hook_path"

  begin_test "$hook_name: fires and writes audit line"
  rm -f "$AUDIT_DIR/$audit_file" 2>/dev/null
  if printf '%s' "$payload" | bash "$hook_path" >/dev/null 2>&1; then
    if [ -s "$AUDIT_DIR/$audit_file" ]; then pass
    else fail "no audit line written to $AUDIT_DIR/$audit_file"
    fi
  else
    fail "hook exited non-zero on valid input"
  fi

  begin_test "$hook_name: respects $disable_var=0"
  rm -f "$AUDIT_DIR/$audit_file" 2>/dev/null
  if env "$disable_var=0" bash -c "printf '%s' '$payload' | bash '$hook_path'" >/dev/null 2>&1; then
    if [ ! -s "$AUDIT_DIR/$audit_file" ]; then pass
    else fail "audit file written despite disable env var"
    fi
  else
    fail "hook exited non-zero when disabled"
  fi

  begin_test "$hook_name: survives malformed JSON"
  rm -f "$AUDIT_DIR/$audit_file" 2>/dev/null
  if printf '%s' '{not valid json' | bash "$hook_path" >/dev/null 2>&1; then
    pass
  else
    fail "hook crashed on malformed input"
  fi
}

# cron-discovery
run_basic_suite \
  "cron-discovery" \
  "cron-payloads.jsonl" \
  "SUPERCHARGER_CRON_DISCOVERY" \
  '{"hook_event_name":"PreToolUse","tool_name":"CronCreate","tool_input":{"schedule":"0 9 * * *","prompt":"run audit"},"session_id":"t1","cwd":"/tmp"}'

# subagent-discovery
run_basic_suite \
  "subagent-discovery" \
  "subagent-payloads.jsonl" \
  "SUPERCHARGER_SUBAGENT_DISCOVERY" \
  '{"hook_event_name":"SubagentStart","session_id":"t1","subagent_id":"a1","parent_agent_id":"root","depth":1,"subagent_type":"Scientist","cwd":"/tmp"}'

# elicitation-discovery
run_basic_suite \
  "elicitation-discovery" \
  "elicitation-payloads.jsonl" \
  "SUPERCHARGER_ELICITATION_DISCOVERY" \
  '{"hook_event_name":"Elicitation","session_id":"t1","server_name":"x","message":"Enter your API token","schema":{"type":"object","properties":{"token":{"type":"string"}}},"cwd":"/tmp"}'

# Elicitation-specific privacy test: response values must NOT appear in audit log.
begin_test "elicitation-discovery: response values are NOT logged"
ELC_HOOK="$REPO_DIR/hooks/elicitation-discovery.sh"
SECRET="ghp_supercharger_test_redacted_value_42"
rm -f "$AUDIT_DIR/elicitation-payloads.jsonl" 2>/dev/null
PAYLOAD=$(printf '{"hook_event_name":"ElicitationResult","session_id":"t1","server_name":"x","accepted":true,"result":{"token":"%s","otp":"123456"},"cwd":"/tmp"}' "$SECRET")
printf '%s' "$PAYLOAD" | bash "$ELC_HOOK" >/dev/null 2>&1
if [ -s "$AUDIT_DIR/elicitation-payloads.jsonl" ]; then
  if grep -q "$SECRET" "$AUDIT_DIR/elicitation-payloads.jsonl"; then
    fail "secret value leaked into elicitation audit log"
  elif grep -q "123456" "$AUDIT_DIR/elicitation-payloads.jsonl"; then
    fail "OTP value leaked into elicitation audit log"
  else
    pass
  fi
else
  fail "no audit line written for ElicitationResult"
fi

teardown_test_home

echo ""
echo "$TESTS_PASSED passed, $TESTS_FAILED failed ($((TESTS_PASSED + TESTS_FAILED)) total)"
exit $TESTS_FAILED
