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

# Disabled hooks content — loaded once at init time, bash 3.2 compatible
_DISABLED_HOOKS_CONTENT=""

_load_disabled_hooks() {
  _DISABLED_HOOKS_CONTENT=""
  local disabled_file="$HOME/.claude/supercharger/scope/.disabled-hooks"
  [ ! -f "$disabled_file" ] && return
  _DISABLED_HOOKS_CONTENT=$(<"$disabled_file")
}

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
    # $EPOCHREALTIME (bash 5+): "seconds.microseconds" — convert to ms, zero fork
    if [[ -n "${EPOCHREALTIME:-}" ]]; then
      HOOK_START_MS=$(( ${EPOCHREALTIME/./} / 1000 ))
    else
      HOOK_START_MS=$(python3 -c "import time; print(int(time.time()*1000))" 2>/dev/null || echo "0")
    fi
  fi

  _load_disabled_hooks
}

check_hook_disabled() {
  local hook_name="${1:-}"
  [ -z "$hook_name" ] && return 1
  [ -z "$_DISABLED_HOOKS_CONTENT" ] && return 1
  # Exact line match — bash 3.2 compatible case pattern
  case $'\n'"$_DISABLED_HOOKS_CONTENT"$'\n' in
    *$'\n'"$hook_name"$'\n'*) return 0 ;;
    *) return 1 ;;
  esac
}

# Returns 0 (true) if the given hook should be skipped in the current profile
# Usage: hook_profile_skip "quality-gate" && exit 0
hook_profile_skip() {
  local hook_name="${1:-}"
  local profile="${SUPERCHARGER_PROFILE:-standard}"
  [ "$profile" = "standard" ] && return 1  # nothing skipped

  if [ "$profile" = "minimal" ]; then
    case "$hook_name" in
      quality-gate|typecheck|repetition-detector|dep-vuln-scanner|\
      mcp-tracker|failure-tracker|session-checkpoint|context-advisor|\
      rate-limit-advisor|thinking-budget|adaptive-economy)
        return 0 ;;
    esac
  fi
  return 1
}

# Default initialisation (no project dir yet — hooks should re-call after reading input)
init_hook_suppress
