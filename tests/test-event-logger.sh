#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

HOOK="$REPO_DIR/hooks/event-logger.sh"

setup_test_home
LOG_FILE="$HOME/.claude/supercharger/events.log"

run_event_logger() {
  local event_type="$1"
  local json_input="$2"
  echo "$json_input" | bash "$HOOK" "$event_type" 2>/dev/null
}

echo "=== Event Logger Hook Tests ==="

begin_test "event-logger: creates log file on first run"
run_event_logger "task_created" '{"task_name":"test-task"}'
assert_file_exists "$LOG_FILE" && pass

begin_test "event-logger: logs permission_denied with tool name"
run_event_logger "permission_denied" '{"tool_name":"Bash","reason":"blocked"}'
assert_file_contains "$LOG_FILE" "permission_denied" && pass

begin_test "event-logger: logs task_created with task name"
run_event_logger "task_created" '{"task_name":"my-task"}'
assert_file_contains "$LOG_FILE" "task=my-task" && pass

begin_test "event-logger: logs task_completed with status"
run_event_logger "task_completed" '{"task_name":"my-task","status":"done"}'
assert_file_contains "$LOG_FILE" "task_completed" && pass

begin_test "event-logger: logs subagent_stop with agent name"
run_event_logger "subagent_stop" '{"agent_name":"debugger"}'
assert_file_contains "$LOG_FILE" "agent=debugger" && pass

begin_test "event-logger: logs tool_failure with tool and error"
run_event_logger "tool_failure" '{"tool_name":"Bash","error":"command not found"}'
assert_file_contains "$LOG_FILE" "tool=Bash" && pass

begin_test "event-logger: exits 0"
exit_code=$(echo '{}' | bash "$HOOK" "unknown" >/dev/null 2>&1; echo $?)
assert_exit_code 0 "$exit_code" && pass

begin_test "event-logger: handles malformed JSON without crashing"
exit_code=$(echo 'not-json' | bash "$HOOK" "task_created" >/dev/null 2>&1; echo $?)
assert_exit_code 0 "$exit_code" && pass

begin_test "event-logger: log entries include ISO timestamp"
run_event_logger "config_change" '{"key":"hooks"}'
if grep -qE '[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z' "$LOG_FILE"; then pass; else fail "no ISO timestamp in log"; fi

begin_test "event-logger: log rotates when over 500 lines"
# Write 510 lines to the log
for i in $(seq 1 510); do
  echo "2026-01-01T00:00:00Z filler detail=line${i}" >> "$LOG_FILE"
done
run_event_logger "task_created" '{"task_name":"trigger-rotate"}'
line_count=$(wc -l < "$LOG_FILE" | tr -d ' ')
if [ "$line_count" -le 500 ]; then pass; else fail "log not rotated (${line_count} lines)"; fi

teardown_test_home
report
