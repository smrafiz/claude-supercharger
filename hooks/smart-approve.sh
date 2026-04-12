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

allow() {
  echo "[Supercharger] smart-approve: auto-approved ${TOOL_NAME}" >&2
  printf '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}\n'
  exit 0
}

# Always-safe tools
case "$TOOL_NAME" in
  Read|Glob|Grep|LS|ls)
    allow
    ;;
esac

# For Bash, inspect the command
if [ "$TOOL_NAME" = "Bash" ]; then
  COMMAND=$(printf '%s\n' "$_INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
  if [ -z "$COMMAND" ]; then
    COMMAND=$(printf '%s\n' "$_INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('command',''))" 2>/dev/null || echo "")
  fi

  [ -z "$COMMAND" ] && exit 0

  # --help / --version flag anywhere in the command
  if printf '%s\n' "$COMMAND" | grep -qE '(^|[[:space:]])--(help|version)([[:space:]]|$)'; then
    allow
  fi

  # Read-only shell, git, and search commands (consolidated)
  if printf '%s\n' "$COMMAND" | grep -qE '^[[:space:]]*(ls|pwd|cat|head|tail|printf|which|type|grep|find|rg)([[:space:]]|$)'; then
    allow
  fi

  # Read-only git subcommands
  if printf '%s\n' "$COMMAND" | grep -qE '^[[:space:]]*git[[:space:]]+(status|log|diff|branch|show|remote|tag)([[:space:]]|$)'; then
    allow
  fi

  # command -v (tool existence check)
  if printf '%s\n' "$COMMAND" | grep -qE '^[[:space:]]*command[[:space:]]+-v[[:space:]]'; then
    allow
  fi

  # Test runners (consolidated)
  if printf '%s\n' "$COMMAND" | grep -qE '^[[:space:]]*(npm|yarn|pnpm)[[:space:]]+test([[:space:]]|$)|^[[:space:]]*(cargo|go)[[:space:]]+test([[:space:]]|$)|^[[:space:]]*pytest([[:space:]]|$)'; then
    allow
  fi

  # curl — only if no explicit non-GET method (-X POST/PUT/DELETE/PATCH or --data / -d)
  if printf '%s\n' "$COMMAND" | grep -qE '^[[:space:]]*curl[[:space:]]'; then
    if ! printf '%s\n' "$COMMAND" | grep -qiE '(-X[[:space:]]*(POST|PUT|DELETE|PATCH)|--request[[:space:]]*(POST|PUT|DELETE|PATCH)|-d[[:space:]]|--data[[:space:]]|--data-raw[[:space:]]|--data-binary[[:space:]])'; then
      allow
    fi
  fi
fi

# Everything else: pass through, let Claude Code decide
exit 0
