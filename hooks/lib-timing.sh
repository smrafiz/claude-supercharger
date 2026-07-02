#!/usr/bin/env bash
# Claude Supercharger — Standalone Timing Instrumentation
# Source this in any hook that does NOT source lib-suppress.sh, to get
# /perf coverage. Single line at the top: . "$HOOKS_DIR/lib-timing.sh"
#
# Activates only when ~/.claude/supercharger/scope/.profiling exists.
# Skips if a trap on EXIT is already set (preserves hook cleanup logic).
# Hook name is derived by walking BASH_SOURCE past lib-timing.sh itself.

# v2.7.45: always-on SLOW-hook timing when EPOCHREALTIME is available (bash 5+,
# zero-fork clock); full profiling via the .profiling sentinel (logs every fire,
# and enables timing on bash 3.2 where the clock needs a python fork).
_HOOK_PERF_FULL=0
[ -f "$HOME/.claude/supercharger/scope/.profiling" ] && _HOOK_PERF_FULL=1
if [ "$_HOOK_PERF_FULL" = 1 ] || [ -n "${EPOCHREALTIME:-}" ]; then
  # Skip if hook already has its own EXIT trap or already sourced lib-suppress.sh
  # (which provides the same instrumentation).
  if [ -z "${HOOK_NAME:-}" ] && [ -z "$(trap -p EXIT)" ]; then
    if [[ -n "${EPOCHREALTIME:-}" ]]; then
      HOOK_START_MS=$(( ${EPOCHREALTIME/./} / 1000 ))
    else
      HOOK_START_MS=$(python3 -c "import time; print(int(time.time()*1000))" 2>/dev/null || echo "0")
    fi

    # Walk BASH_SOURCE past lib-timing.sh to find the actual hook script.
    _i=1
    HOOK_NAME=""
    while [ $_i -lt ${#BASH_SOURCE[@]} ]; do
      _src="${BASH_SOURCE[$_i]:-}"
      case "$_src" in
        */lib-timing.sh|*/lib-suppress.sh|"") _i=$((_i + 1)); continue ;;
        *) HOOK_NAME=$(basename "$_src" .sh); break ;;
      esac
    done
    [ -z "$HOOK_NAME" ] && HOOK_NAME="unknown"

    _emit_hook_timing_lt() {
      [ "${HOOK_START_MS:-0}" = "0" ] && return
      [ -z "${HOOK_NAME:-}" ] && return
      local end_ms
      if [[ -n "${EPOCHREALTIME:-}" ]]; then
        end_ms=$(( ${EPOCHREALTIME/./} / 1000 ))
      else
        end_ms=$(python3 -c "import time; print(int(time.time()*1000))" 2>/dev/null || echo "$HOOK_START_MS")
      fi
      local elapsed=$((end_ms - HOOK_START_MS))
      # v2.7.45: only record slow invocations outside full-profiling mode.
      if [ "${_HOOK_PERF_FULL:-0}" != 1 ] && [ "$elapsed" -lt "${SUPERCHARGER_PERF_THRESHOLD_MS:-40}" ]; then
        return
      fi
      local audit_dir="$HOME/.claude/supercharger/audit"
      mkdir -p "$audit_dir" 2>/dev/null || return
      local date_str
      date_str=$(date +%Y-%m-%d 2>/dev/null) || return
      printf '{"hook":"%s","elapsed_ms":%d,"ts":%d}\n' "$HOOK_NAME" "$elapsed" "$end_ms" \
        >> "$audit_dir/${date_str}.jsonl" 2>/dev/null || true
    }

    trap _emit_hook_timing_lt EXIT
  fi
fi
