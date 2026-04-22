#!/usr/bin/env bash
# Claude Supercharger — Hook Output Suppress Helper
# Source this file to get HOOK_SUPPRESS (true/false) and init_hook_suppress().
#
# Output is suppressed by default. To show hook output:
#   Global:  touch ~/.claude/supercharger/scope/.debug-hooks
#   Project: touch .supercharger-debug  (in project root)
#
# Usage:
#   . "$HOOKS_DIR/lib-suppress.sh"          # sets HOOK_SUPPRESS=true by default
#   ...read stdin, extract PROJECT_DIR...
#   init_hook_suppress "$PROJECT_DIR"        # re-evaluate with actual project dir

init_hook_suppress() {
  local dir="${1:-}"
  HOOK_SUPPRESS=true
  if [ -f "$HOME/.claude/supercharger/scope/.debug-hooks" ]; then
    HOOK_SUPPRESS=false; return
  fi
  if [ -n "$dir" ] && [ -f "${dir}/.supercharger-debug" ]; then
    HOOK_SUPPRESS=false; return
  fi
  # Fallback: check PWD (unreliable in hook context — prefer passing dir explicitly)
  [ -f "${PWD}/.supercharger-debug" ] && HOOK_SUPPRESS=false || true

  # Timing instrumentation — only active when profiler is running
  HOOK_START_MS=0
  if [ -f "$HOME/.claude/supercharger/scope/.profiling" ]; then
    HOOK_START_MS=$(python3 -c "import time; print(int(time.time()*1000))" 2>/dev/null || echo "0")
  fi
}

# Default initialisation (no project dir yet — hooks should re-call after reading input)
init_hook_suppress
