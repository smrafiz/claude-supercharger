#!/usr/bin/env bash
# Claude Supercharger — Repeated Failure Tracker
# Event: PostToolUse | Matcher: Bash
# Detects when the same command fails repeatedly and logs the pattern.

set -euo pipefail

_INPUT=$(cat)

# Check if command failed (non-zero exit or error in output)
EXIT_CODE=$(printf '%s\n' "$_INPUT" | jq -r '.tool_response.exit_code // empty' 2>/dev/null)
[ -z "$EXIT_CODE" ] && exit 0
[ "$EXIT_CODE" = "0" ] && exit 0

# Get the command
COMMAND=$(printf '%s\n' "$_INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

# Normalize command for comparison (first 100 chars, strip args that change)
CMD_KEY=$(printf '%.100s' "$COMMAND" | sed 's/[0-9]\{4,\}//g')

SCOPE_DIR="$HOME/.claude/supercharger/scope"
FAILURES_LOG="$SCOPE_DIR/.failed-commands"
mkdir -p "$SCOPE_DIR" 2>/dev/null || true

# Count how many times this command pattern failed recently
FAIL_COUNT=0
if [ -f "$FAILURES_LOG" ]; then
  FAIL_COUNT=$(grep -cF "$CMD_KEY" "$FAILURES_LOG" 2>/dev/null || echo "0")
fi

# Log the failure
printf '[%s] exit=%s — %s\n' "$(date '+%Y-%m-%d %H:%M')" "$EXIT_CODE" "$CMD_KEY" >> "$FAILURES_LOG" 2>/dev/null || true

# If 3+ failures of same pattern, warn Claude
if [ "$FAIL_COUNT" -ge 2 ]; then
  CONTEXT="[LEARNING] The command pattern '$(printf '%.60s' "$CMD_KEY")' has failed ${FAIL_COUNT} times. Try a different approach instead of retrying the same command."
  CONTEXT_JSON=$(printf '%s' "$CONTEXT" | jq -Rs '.' 2>/dev/null || printf '"%s"' "$(printf '%s' "$CONTEXT" | tr -d '"\\' | tr '\n' ' ')")
  printf '{"systemMessage":%s}\n' "$CONTEXT_JSON"
  echo "[Supercharger] failure-tracker: command failed ${FAIL_COUNT}x — nudging Claude to try different approach" >&2
fi

exit 0
