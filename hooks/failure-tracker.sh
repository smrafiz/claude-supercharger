#!/usr/bin/env bash
# Claude Supercharger — Repeated Failure Tracker
# Event: PostToolUse | Matcher: Bash
# Detects when the same command fails repeatedly and logs the pattern.

set -euo pipefail
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh"

_INPUT=$(cat)
PROJECT_DIR=$(printf '%s\n' "$_INPUT" | jq -r '.cwd // .workspace.current_dir // empty' 2>/dev/null || true); [ -z "$PROJECT_DIR" ] && PROJECT_DIR="$PWD"
init_hook_suppress "$PROJECT_DIR"
hook_profile_skip "failure-tracker" && exit 0

# v2.7.15: CC's PostToolUse Bash payload has NO exit_code (verified: tool_response
# = {interrupted,isImage,noOutputExpected,stderr,stdout}), so the old
# `.tool_response.exit_code` read was always empty → this hook exited on every
# command and never learned. Infer failure from the signals CC DOES provide:
# `interrupted=true` (cancelled/timed out), or a STRONG error marker in stderr/
# stdout. The markers are unambiguous failures (command not found, Traceback,
# fatal:, …) so benign tools that merely write progress/warnings to stderr (git,
# npm) don't trip a false "repeated failure" nudge.
INTERRUPTED=$(printf '%s\n' "$_INPUT" | jq -r '.tool_response.interrupted // false' 2>/dev/null || echo false)
ERRTEXT=$(printf '%s\n' "$_INPUT" | jq -r '(.tool_response.stderr // "") + "\n" + (.tool_response.stdout // "")' 2>/dev/null | head -c 4000 || true)

FAIL_MARKERS='command not found|: not found|No such file or directory|Permission denied|fatal:|Traceback \(most recent call|Segmentation fault|core dumped|Cannot find module|ModuleNotFoundError|ImportError|ENOENT|EACCES|exited with (code )?[1-9]|exit code [1-9]|panic:|undefined reference|[a-zA-Z]*Error:|FAILED|assertion failed|cannot access|unknown command|No such command'

FAILED=false
[ "$INTERRUPTED" = "true" ] && FAILED=true
if [ "$FAILED" = "false" ] && printf '%s' "$ERRTEXT" | LC_ALL=C grep -qiE "$FAIL_MARKERS"; then
  FAILED=true
fi
[ "$FAILED" = "false" ] && exit 0

# Get the command
COMMAND=$(printf '%s\n' "$_INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)
[ -z "$COMMAND" ] && exit 0

# Normalize command for comparison (first 100 chars, strip args that change)
CMD_KEY=$(printf '%.100s' "$COMMAND" | sed 's/[0-9]\{4,\}//g')

SCOPE_DIR="$HOME/.claude/supercharger/scope"
# v2.7.15: key by project so a command that failed in repo A doesn't trip the
# nudge in repo B months later, and cap the file so it can't grow unbounded.
PROJ_HASH=$(printf '%s' "$PROJECT_DIR" | md5sum 2>/dev/null | cut -c1-8 || printf '%s' "$PROJECT_DIR" | md5 -q 2>/dev/null | cut -c1-8 || echo global)
FAILURES_LOG="$SCOPE_DIR/.failed-commands-${PROJ_HASH}"
mkdir -p "$SCOPE_DIR" 2>/dev/null || true

# Count how many times this command pattern failed recently
FAIL_COUNT=0
if [ -f "$FAILURES_LOG" ]; then
  # v2.6.42: awk emits exactly one number; `grep -c | || echo 0` doubled
  # output on zero matches and aborted `[ "$FAIL_COUNT" -ge 2 ]` under set -e.
  FAIL_COUNT=$(awk -v k="$CMD_KEY" 'index($0,k){c++} END{print c+0}' "$FAILURES_LOG" 2>/dev/null || echo 0)
fi

# Log the failure
printf '[%s] fail — %s\n' "$(date '+%Y-%m-%d %H:%M')" "$CMD_KEY" >> "$FAILURES_LOG" 2>/dev/null || true
# Cap the log at 200 lines (keep most recent) so it can't grow unbounded.
if [ -f "$FAILURES_LOG" ] && [ "$(wc -l < "$FAILURES_LOG" 2>/dev/null || echo 0)" -gt 200 ]; then
  tail -200 "$FAILURES_LOG" > "$FAILURES_LOG.tmp" 2>/dev/null && mv "$FAILURES_LOG.tmp" "$FAILURES_LOG" 2>/dev/null || true
fi

# If 3+ failures of same pattern, warn Claude
if [ "$FAIL_COUNT" -ge 2 ]; then
  CONTEXT="[LEARNING] The command pattern '$(printf '%.60s' "$CMD_KEY")' has failed ${FAIL_COUNT} times. Try a different approach instead of retrying the same command."
  CONTEXT_JSON=$(printf '%s' "$CONTEXT" | jq -Rs '.' 2>/dev/null || printf '"%s"' "$(printf '%s' "$CONTEXT" | tr -d '"\\' | tr '\n' ' ')")
  printf '{"systemMessage":%s,"suppressOutput":%s}\n' "$CONTEXT_JSON" "$HOOK_SUPPRESS"
  echo "[Supercharger] failure-tracker: command failed ${FAIL_COUNT}x — nudging Claude to try different approach" >&2
fi

exit 0
