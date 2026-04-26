#!/usr/bin/env bash
# Claude Supercharger — Smart Approve
# Event: PermissionRequest
# Auto-approves known-safe tool calls to reduce user prompts.
# Uses updatedPermissions for session persistence — approved once, never asked again.

set -euo pipefail

_INPUT=$(cat)

TOOL_NAME=$(printf '%s\n' "$_INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
if [ -z "$TOOL_NAME" ]; then
  TOOL_NAME=$(printf '%s\n' "$_INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_name',''))" 2>/dev/null || echo "")
fi

[ -z "$TOOL_NAME" ] && exit 0

# Get PROJECT_DIR for project-scoped approvals
PROJECT_DIR=$(printf '%s\n' "$_INPUT" | jq -r '.cwd // empty' 2>/dev/null)
[ -z "$PROJECT_DIR" ] && PROJECT_DIR="$PWD"

allow_tool() {
  echo "[Supercharger] smart-approve: auto-approved ${TOOL_NAME}" >&2
  printf '{"permissionDecision":"allow","reason":"auto-approved read-only tool %s"}\n' "$TOOL_NAME"
  exit 0
}

allow_cmd() {
  local rule="$1"
  echo "[Supercharger] smart-approve: auto-approved ${TOOL_NAME} (${rule})" >&2
  printf '{"permissionDecision":"allow","reason":"auto-approved safe command: %s"}\n' "$rule"
  exit 0
}

allow_path() {
  local pattern="$1"
  echo "[Supercharger] smart-approve: auto-approved ${TOOL_NAME} (${pattern})" >&2
  printf '{"permissionDecision":"allow","reason":"auto-approved safe path pattern: %s"}\n' "$pattern"
  exit 0
}

# --- Always-safe tools ---
case "$TOOL_NAME" in
  Read|Glob|Grep|LS|ls)
    allow_tool
    ;;
esac

# --- Write/Edit: auto-approve if file is inside project directory ---
if [ "$TOOL_NAME" = "Write" ] || [ "$TOOL_NAME" = "Edit" ] || [ "$TOOL_NAME" = "MultiEdit" ]; then
  FILE_PATH=$(printf '%s\n' "$_INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
  if [ -n "$FILE_PATH" ] && [ -n "$PROJECT_DIR" ]; then
    # Resolve to absolute path
    case "$FILE_PATH" in
      /*) ABS_PATH="$FILE_PATH" ;;
      *)  ABS_PATH="${PROJECT_DIR}/${FILE_PATH}" ;;
    esac
    # Allow if inside project directory
    case "$ABS_PATH" in
      "${PROJECT_DIR}"/*)
        allow_path "${PROJECT_DIR}/**"
        ;;
    esac
  fi
  exit 0
fi

# --- Bash commands ---
if [ "$TOOL_NAME" = "Bash" ]; then
  COMMAND=$(printf '%s\n' "$_INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
  if [ -z "$COMMAND" ]; then
    COMMAND=$(printf '%s\n' "$_INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('command',''))" 2>/dev/null || echo "")
  fi

  [ -z "$COMMAND" ] && exit 0

  BASE_CMD=$(printf '%s\n' "$COMMAND" | awk '{print $1}')

  # --help / --version
  if printf '%s\n' "$COMMAND" | grep -qE '(^|[[:space:]])--(help|version)([[:space:]]|$)'; then
    allow_cmd "${BASE_CMD} --help"
  fi

  # Read-only shell commands
  if printf '%s\n' "$COMMAND" | grep -qE '^[[:space:]]*(ls|pwd|cat|head|tail|printf|which|type|grep|find|rg|wc|sort|uniq|diff|file|stat|env|printenv)([[:space:]]|$)'; then
    allow_cmd "${BASE_CMD} *"
  fi

  # Read-only git subcommands
  if printf '%s\n' "$COMMAND" | grep -qE '^[[:space:]]*git[[:space:]]+(status|log|diff|branch|show|remote|tag|stash list|rev-parse|describe)([[:space:]]|$)'; then
    GIT_SUB=$(printf '%s\n' "$COMMAND" | awk '{print $2}')
    allow_cmd "git ${GIT_SUB} *"
  fi

  # command -v (tool existence check)
  if printf '%s\n' "$COMMAND" | grep -qE '^[[:space:]]*command[[:space:]]+-v[[:space:]]'; then
    allow_cmd "command -v *"
  fi

  # Test runners
  if printf '%s\n' "$COMMAND" | grep -qE '^[[:space:]]*(npm|yarn|pnpm)[[:space:]]+test([[:space:]]|$)|^[[:space:]]*(cargo|go)[[:space:]]+test([[:space:]]|$)|^[[:space:]]*pytest([[:space:]]|$)|^[[:space:]]*vitest([[:space:]]|$)|^[[:space:]]*jest([[:space:]]|$)'; then
    allow_cmd "${COMMAND%% *} test *"
  fi

  # Package manager run/build/dev commands
  if printf '%s\n' "$COMMAND" | grep -qE '^[[:space:]]*(npm|yarn|pnpm|bun)[[:space:]]+(run|build|dev|start|lint|format|typecheck|type-check)([[:space:]]|$)'; then
    PM_CMD=$(printf '%s\n' "$COMMAND" | awk '{print $1 " " $2}')
    allow_cmd "${PM_CMD} *"
  fi

  # Node/Python/Ruby running project scripts
  if printf '%s\n' "$COMMAND" | grep -qE '^[[:space:]]*(node|python3?|ruby|tsx|ts-node|npx|bunx)[[:space:]]'; then
    allow_cmd "${BASE_CMD} *"
  fi

  # curl — GET only
  if printf '%s\n' "$COMMAND" | grep -qE '^[[:space:]]*curl[[:space:]]'; then
    if ! printf '%s\n' "$COMMAND" | grep -qiE '(-X[[:space:]]*(POST|PUT|DELETE|PATCH)|--request[[:space:]]*(POST|PUT|DELETE|PATCH)|-d[[:space:]]|--data[[:space:]]|--data-raw[[:space:]]|--data-binary[[:space:]])'; then
      allow_cmd "curl *"
    fi
  fi

  # Build tools
  if printf '%s\n' "$COMMAND" | grep -qE '^[[:space:]]*(make|cargo build|go build|tsc|gcc|g\+\+|rustc|javac)([[:space:]]|$)'; then
    allow_cmd "${BASE_CMD} *"
  fi
fi

# Everything else: pass through, let Claude Code decide
exit 0
