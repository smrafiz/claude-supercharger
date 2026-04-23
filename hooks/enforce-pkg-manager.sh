#!/usr/bin/env bash
# Claude Supercharger — Package Manager Enforcement Hook
# Event: PreToolUse | Matcher: Bash
# Detects lockfiles and blocks the wrong package manager.

set -euo pipefail

_INPUT=$(cat)
COMMAND=$(printf '%s\n' "$_INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
if [ -z "$COMMAND" ]; then
  COMMAND=$(printf '%s\n' "$_INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('command',''))" 2>/dev/null || echo "")
fi

if [ -z "$COMMAND" ]; then
  exit 0
fi

source "$(dirname "${BASH_SOURCE[0]}")/cmd-normalize.sh"
CMD=$(normalize_cmd "$COMMAND")

PROJECT_DIR=$(printf '%s\n' "$_INPUT" | jq -r '.cwd // empty' 2>/dev/null)
[ -z "$PROJECT_DIR" ] && PROJECT_DIR=$(printf '%s\n' "$_INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('cwd',''))" 2>/dev/null || echo "")
[ -z "$PROJECT_DIR" ] && PROJECT_DIR="$(pwd)"

block() {
  echo "" >&2
  echo "Supercharger blocked this command." >&2
  echo "  Reason : $1" >&2
  echo "  Command: $COMMAND" >&2
  echo "  This command is permanently blocked. Run it in your terminal directly if needed." >&2
  echo "" >&2
  exit 2
}

# pnpm project — block npm
if [ -f "$PROJECT_DIR/pnpm-lock.yaml" ] && [ ! -L "$PROJECT_DIR/pnpm-lock.yaml" ]; then
  if [[ "$CMD" =~ ^npm[[:space:]]+(install|run|exec|ci|start|test|build|add|remove|update|publish) ]]; then
    block "This project uses pnpm (pnpm-lock.yaml found). Use pnpm instead of npm."
  fi
fi

# yarn project — block npm install/add
if [ -f "$PROJECT_DIR/yarn.lock" ] && [ ! -L "$PROJECT_DIR/yarn.lock" ]; then
  if [[ "$CMD" =~ ^npm[[:space:]]+(install|ci|add|remove|update) ]]; then
    block "This project uses yarn (yarn.lock found). Use yarn instead of npm."
  fi
fi

# uv/poetry project — block raw pip install
if { [ -f "$PROJECT_DIR/uv.lock" ] && [ ! -L "$PROJECT_DIR/uv.lock" ]; } || { [ -f "$PROJECT_DIR/poetry.lock" ] && [ ! -L "$PROJECT_DIR/poetry.lock" ]; }; then
  if [[ "$CMD" =~ ^pip[[:space:]]+install ]]; then
    manager="uv"
    [ -f "$PROJECT_DIR/poetry.lock" ] && manager="poetry"
    block "This project uses $manager. Use '$manager add' instead of pip install."
  fi
fi

# bun project — block npm
if { [ -f "$PROJECT_DIR/bun.lockb" ] && [ ! -L "$PROJECT_DIR/bun.lockb" ]; } || { [ -f "$PROJECT_DIR/bun.lock" ] && [ ! -L "$PROJECT_DIR/bun.lock" ]; }; then
  if [[ "$CMD" =~ ^npm[[:space:]]+(install|run|exec|ci|start|test|build|add|remove|update) ]]; then
    block "This project uses bun (bun.lockb found). Use bun instead of npm."
  fi
fi

exit 0
