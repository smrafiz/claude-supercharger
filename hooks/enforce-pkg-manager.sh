#!/usr/bin/env bash
# Claude Supercharger — Package Manager Enforcement Hook
# Event: PreToolUse | Matcher: Bash
# Detects lockfiles and blocks the wrong package manager.

set -euo pipefail

COMMAND=$(python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('command',''))" 2>/dev/null || echo "")

if [ -z "$COMMAND" ]; then
  exit 0
fi

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"

block() {
  echo "BLOCKED by Supercharger: $1" >&2
  exit 2
}

# pnpm project — block npm
if [ -f "$PROJECT_DIR/pnpm-lock.yaml" ] && [ ! -L "$PROJECT_DIR/pnpm-lock.yaml" ]; then
  if printf '%s\n' "$COMMAND" | grep -qE '^\s*npm\s+(install|run|exec|ci|start|test|build|add|remove|update|publish)\b'; then
    block "This project uses pnpm (pnpm-lock.yaml found). Use pnpm instead of npm."
  fi
fi

# yarn project — block npm install/add
if [ -f "$PROJECT_DIR/yarn.lock" ] && [ ! -L "$PROJECT_DIR/yarn.lock" ]; then
  if printf '%s\n' "$COMMAND" | grep -qE '^\s*npm\s+(install|ci|add|remove|update)\b'; then
    block "This project uses yarn (yarn.lock found). Use yarn instead of npm."
  fi
fi

# uv/poetry project — block raw pip install
if { [ -f "$PROJECT_DIR/uv.lock" ] && [ ! -L "$PROJECT_DIR/uv.lock" ]; } || { [ -f "$PROJECT_DIR/poetry.lock" ] && [ ! -L "$PROJECT_DIR/poetry.lock" ]; }; then
  if printf '%s\n' "$COMMAND" | grep -qE '^\s*pip\s+install\b'; then
    manager="uv"
    [ -f "$PROJECT_DIR/poetry.lock" ] && manager="poetry"
    block "This project uses $manager. Use '$manager add' instead of pip install."
  fi
fi

# bun project — block npm
if { [ -f "$PROJECT_DIR/bun.lockb" ] && [ ! -L "$PROJECT_DIR/bun.lockb" ]; } || { [ -f "$PROJECT_DIR/bun.lock" ] && [ ! -L "$PROJECT_DIR/bun.lock" ]; }; then
  if printf '%s\n' "$COMMAND" | grep -qE '^\s*npm\s+(install|run|exec|ci|start|test|build|add|remove|update)\b'; then
    block "This project uses bun (bun.lockb found). Use bun instead of npm."
  fi
fi

exit 0
