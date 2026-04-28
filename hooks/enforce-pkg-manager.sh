#!/usr/bin/env bash
# Claude Supercharger — Package Manager Enforcement Hook
# Event: PreToolUse | Matcher: Bash
# Detects lockfiles and blocks the wrong package manager.

set -euo pipefail

_INPUT=$(cat)

# Single python3 fork extracting both fields — replaces 2 jq + 2 python3 fallbacks.
# Output format: <command>\x1F<cwd>  (US separator, never appears in shell input)
EXTRACTED=$(printf '%s\n' "$_INPUT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    cmd = ((d.get('tool_input') or {}).get('command') or '')
    cwd = d.get('cwd') or ''
    print(cmd + '\x1f' + cwd)
except Exception:
    print('\x1f')
" 2>/dev/null)

COMMAND="${EXTRACTED%%$'\x1f'*}"
PROJECT_DIR="${EXTRACTED#*$'\x1f'}"

[ -z "$COMMAND" ] && exit 0
[ -z "$PROJECT_DIR" ] && PROJECT_DIR="$PWD"

source "$(dirname "${BASH_SOURCE[0]}")/cmd-normalize.sh"
CMD=$(normalize_cmd "$COMMAND")

# Per-segment view — protects against `safe && npm install` bypass.
SEGMENTS=$(split_segments "$CMD")
[ -z "$SEGMENTS" ] && SEGMENTS="$CMD"

block() {
  echo "" >&2
  echo "Supercharger blocked this command." >&2
  echo "  Reason : $1" >&2
  echo "  Command: $COMMAND" >&2
  echo "  This command is permanently blocked. Run it in your terminal directly if needed." >&2
  echo "" >&2
  RSN=$(printf '%s' "$1" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || printf '"%s"' "$1")
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":%s}}\n' "$RSN"
  exit 2
}

while IFS= read -r seg; do
  [ -z "$seg" ] && continue

  # pnpm project — block npm
  if [ -f "$PROJECT_DIR/pnpm-lock.yaml" ] && [ ! -L "$PROJECT_DIR/pnpm-lock.yaml" ]; then
    if [[ "$seg" =~ ^npm[[:space:]]+(install|run|exec|ci|start|test|build|add|remove|update|publish) ]]; then
      block "This project uses pnpm (pnpm-lock.yaml found). Use pnpm instead of npm."
    fi
  fi

  # yarn project — block npm install/add
  if [ -f "$PROJECT_DIR/yarn.lock" ] && [ ! -L "$PROJECT_DIR/yarn.lock" ]; then
    if [[ "$seg" =~ ^npm[[:space:]]+(install|ci|add|remove|update) ]]; then
      block "This project uses yarn (yarn.lock found). Use yarn instead of npm."
    fi
  fi

  # uv/poetry project — block raw pip install
  if { [ -f "$PROJECT_DIR/uv.lock" ] && [ ! -L "$PROJECT_DIR/uv.lock" ]; } || { [ -f "$PROJECT_DIR/poetry.lock" ] && [ ! -L "$PROJECT_DIR/poetry.lock" ]; }; then
    if [[ "$seg" =~ ^pip[[:space:]]+install ]]; then
      manager="uv"
      [ -f "$PROJECT_DIR/poetry.lock" ] && manager="poetry"
      block "This project uses $manager. Use '$manager add' instead of pip install."
    fi
  fi

  # bun project — block npm
  if { [ -f "$PROJECT_DIR/bun.lockb" ] && [ ! -L "$PROJECT_DIR/bun.lockb" ]; } || { [ -f "$PROJECT_DIR/bun.lock" ] && [ ! -L "$PROJECT_DIR/bun.lock" ]; }; then
    if [[ "$seg" =~ ^npm[[:space:]]+(install|run|exec|ci|start|test|build|add|remove|update) ]]; then
      block "This project uses bun (bun lockfile found). Use bun instead of npm."
    fi
  fi
done <<< "$SEGMENTS"

exit 0
