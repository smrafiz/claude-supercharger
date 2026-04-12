#!/usr/bin/env bash
# Claude Supercharger — Smart Approve
# Event: PermissionRequest
# Auto-approves known-safe read-only tool calls to reduce user prompts.

set -euo pipefail

_INPUT=$(cat)

TOOL_NAME=$(printf '%s\n' "$_INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
if [ -z "$TOOL_NAME" ]; then
  TOOL_NAME=$(printf '%s\n' "$_INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_name',''))" 2>/dev/null || echo "")
fi

[ -z "$TOOL_NAME" ] && exit 0

allow_tool() {
  # Allow + add permanent session rule so this tool never prompts again
  echo "[Supercharger] smart-approve: auto-approved ${TOOL_NAME} (permanent for session)" >&2
  printf '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow","updatedPermissions":[{"type":"addRules","rules":[{"toolName":"%s"}],"behavior":"allow","destination":"session"}]}}}\n' "$TOOL_NAME"
  exit 0
}

allow_cmd() {
  # Allow + add permanent session rule for this specific command pattern
  local rule="$1"
  echo "[Supercharger] smart-approve: auto-approved ${TOOL_NAME} (${rule})" >&2
  local rule_json
  rule_json=$(printf '%s' "$rule" | jq -Rs '.' 2>/dev/null || printf '"%s"' "$rule")
  printf '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow","updatedPermissions":[{"type":"addRules","rules":[{"toolName":"Bash","ruleContent":%s}],"behavior":"allow","destination":"session"}]}}}\n' "$rule_json"
  exit 0
}

# Always-safe tools — permanently allow for session
case "$TOOL_NAME" in
  Read|Glob|Grep|LS|ls)
    allow_tool
    ;;
esac

# For Bash, inspect the command
if [ "$TOOL_NAME" = "Bash" ]; then
  COMMAND=$(printf '%s\n' "$_INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
  if [ -z "$COMMAND" ]; then
    COMMAND=$(printf '%s\n' "$_INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('command',''))" 2>/dev/null || echo "")
  fi

  [ -z "$COMMAND" ] && exit 0

  # Extract base command for rule creation
  BASE_CMD=$(printf '%s\n' "$COMMAND" | awk '{print $1}')

  # --help / --version flag anywhere in the command
  if printf '%s\n' "$COMMAND" | grep -qE '(^|[[:space:]])--(help|version)([[:space:]]|$)'; then
    allow_cmd "${BASE_CMD} --help"
  fi

  # Read-only shell, git, and search commands (consolidated)
  if printf '%s\n' "$COMMAND" | grep -qE '^[[:space:]]*(ls|pwd|cat|head|tail|printf|which|type|grep|find|rg)([[:space:]]|$)'; then
    allow_cmd "${BASE_CMD} *"
  fi

  # Read-only git subcommands
  if printf '%s\n' "$COMMAND" | grep -qE '^[[:space:]]*git[[:space:]]+(status|log|diff|branch|show|remote|tag)([[:space:]]|$)'; then
    GIT_SUB=$(printf '%s\n' "$COMMAND" | awk '{print $2}')
    allow_cmd "git ${GIT_SUB} *"
  fi

  # command -v (tool existence check)
  if printf '%s\n' "$COMMAND" | grep -qE '^[[:space:]]*command[[:space:]]+-v[[:space:]]'; then
    allow_cmd "command -v *"
  fi

  # Test runners (consolidated)
  if printf '%s\n' "$COMMAND" | grep -qE '^[[:space:]]*(npm|yarn|pnpm)[[:space:]]+test([[:space:]]|$)|^[[:space:]]*(cargo|go)[[:space:]]+test([[:space:]]|$)|^[[:space:]]*pytest([[:space:]]|$)'; then
    allow_cmd "${COMMAND%% *} test *"
  fi

  # curl — only if no explicit non-GET method
  if printf '%s\n' "$COMMAND" | grep -qE '^[[:space:]]*curl[[:space:]]'; then
    if ! printf '%s\n' "$COMMAND" | grep -qiE '(-X[[:space:]]*(POST|PUT|DELETE|PATCH)|--request[[:space:]]*(POST|PUT|DELETE|PATCH)|-d[[:space:]]|--data[[:space:]]|--data-raw[[:space:]]|--data-binary[[:space:]])'; then
      allow_cmd "curl *"
    fi
  fi
fi

# Everything else: pass through, let Claude Code decide
exit 0
