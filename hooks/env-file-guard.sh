#!/usr/bin/env bash
# Claude Supercharger — .env File Protection
# Event: PreToolUse | Matcher: Bash, Read
# Blocks reading/editing .env files (which typically contain credentials).
# Allows .env.example, .env.template, .env.sample, .env.dist (templates).
# Inspired by pchalasani/claude-code-tools/safety-hooks (Apache-2.0).

set -uo pipefail
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh"

_INPUT=$(cat)
PROJECT_DIR=$(printf '%s\n' "$_INPUT" | jq -r '.cwd // empty' 2>/dev/null); [ -z "$PROJECT_DIR" ] && PROJECT_DIR="$PWD"
init_hook_suppress "$PROJECT_DIR"
check_hook_disabled "env-file-guard" && exit 0

block() {
  local reason="$1" preview="$2"
  echo "" >&2
  echo "Supercharger blocked .env access." >&2
  echo "  Reason : $reason" >&2
  echo "  Input  : ${preview:0:120}" >&2
  echo "  .env files commonly contain credentials. If you need this, run it in your terminal." >&2
  echo "" >&2
  RSN=$(printf '%s' "$reason" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))")
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":%s}}\n' "$RSN"
  exit 2
}

TOOL=$(printf '%s\n' "$_INPUT" | jq -r '.tool_name // empty' 2>/dev/null)

# Bash: check command for .env reads/edits
if [ "$TOOL" = "Bash" ]; then
  COMMAND=$(printf '%s\n' "$_INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
  [ -z "$COMMAND" ] && exit 0

  # Allow safe metadata commits/PRs that may mention .env in text
  if printf '%s\n' "$COMMAND" | grep -qE '^\s*(git\s+commit|git\s+tag|gh\s+(pr|issue|release)\s+create)\b'; then
    exit 0
  fi

  # Run the env-detection logic via external python module
  REASON=$(CMD="$COMMAND" python3 "$HOOKS_DIR/env-file-detect.py" 2>/dev/null)
  if [ -n "$REASON" ]; then
    block "$REASON" "$COMMAND"
  fi
  exit 0
fi

# Read tool: block reading .env files directly
if [ "$TOOL" = "Read" ]; then
  FILE_PATH=$(printf '%s\n' "$_INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
  [ -z "$FILE_PATH" ] && exit 0
  base=$(basename "$FILE_PATH")
  case "$base" in
    .env.example|.env.template|.env.sample|.env.dist) exit 0 ;;
  esac
  if [[ "$base" =~ ^\.env(\.[a-zA-Z0-9_-]+)?$ ]]; then
    block "Read of .env file blocked — credentials likely present" "$FILE_PATH"
  fi
  exit 0
fi

exit 0
