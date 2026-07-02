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

# Append a {hook, elapsed_ms, ts} line to today's audit log. Called via EXIT trap
# from init_hook_suppress when the .profiling sentinel is present. Single short
# line per fire — POSIX append is atomic for writes under PIPE_BUF (~4KB), so
# concurrent hook fires don't interleave bytes within a record.
_emit_hook_timing() {
  [ "${HOOK_START_MS:-0}" = "0" ] && return
  [ -z "${HOOK_NAME:-}" ] && return
  local end_ms
  if [[ -n "${EPOCHREALTIME:-}" ]]; then
    end_ms=$(( ${EPOCHREALTIME/./} / 1000 ))
  else
    end_ms=$(python3 -c "import time; print(int(time.time()*1000))" 2>/dev/null || echo "$HOOK_START_MS")
  fi
  local elapsed=$((end_ms - HOOK_START_MS))
  # v2.7.45: outside full-profiling mode, only record SLOW invocations so
  # always-on timing costs ~nothing (2 clock reads + a compare, no I/O) for the
  # fast common case, while still surfacing the hooks worth optimizing in /perf.
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
  # shellcheck disable=SC2034  # HOOK_SUPPRESS is read by every sourcing hook
  [ -f "${PWD}/.supercharger-debug" ] && HOOK_SUPPRESS=false || true

  # Timing instrumentation. v2.7.45: always-on SLOW-hook detection when
  # EPOCHREALTIME is available (bash 5+, zero-fork clock). The full .profiling
  # sentinel logs EVERY fire and also enables timing on bash 3.2 (where the clock
  # needs a python fork, so we don't add it unconditionally there).
  HOOK_START_MS=0
  HOOK_NAME=""
  _HOOK_PERF_FULL=0
  [ -f "$HOME/.claude/supercharger/scope/.profiling" ] && _HOOK_PERF_FULL=1
  if [ "$_HOOK_PERF_FULL" = 1 ] || [ -n "${EPOCHREALTIME:-}" ]; then
    # $EPOCHREALTIME (bash 5+): "seconds.microseconds" — convert to ms, zero fork
    if [[ -n "${EPOCHREALTIME:-}" ]]; then
      HOOK_START_MS=$(( ${EPOCHREALTIME/./} / 1000 ))
    else
      HOOK_START_MS=$(python3 -c "import time; print(int(time.time()*1000))" 2>/dev/null || echo "0")
    fi
    # Walk BASH_SOURCE past lib-suppress.sh to find the actual hook script.
    # init_hook_suppress is called from two places: (a) line 183 of this file
    # (auto-init for hooks that don't re-call), where BASH_SOURCE[1] is also
    # lib-suppress.sh; (b) directly from a hook script. The walk handles both.
    local _i=1
    HOOK_NAME=""
    while [ $_i -lt ${#BASH_SOURCE[@]} ]; do
      local _src="${BASH_SOURCE[$_i]:-}"
      case "$_src" in
        */lib-suppress.sh|"") _i=$((_i + 1)); continue ;;
        *) HOOK_NAME=$(basename "$_src" .sh); break ;;
      esac
    done
    [ -z "$HOOK_NAME" ] && HOOK_NAME="unknown"
    # Only register the EXIT trap if no trap is already set, so we never clobber
    # cleanup logic in hooks that have their own trap. Hooks with their own trap
    # silently skip profiling — partial data is better than broken hooks.
    if [ -z "$(trap -p EXIT)" ]; then
      trap _emit_hook_timing EXIT
    fi
  fi

  _load_disabled_hooks

  # Load project profile from scope file — set SUPERCHARGER_PROFILE if not already set by env
  if [ -z "${SUPERCHARGER_PROFILE:-}" ]; then
    local profile_file="$HOME/.claude/supercharger/scope/.profile"
    [ -f "$profile_file" ] && SUPERCHARGER_PROFILE=$(<"$profile_file") || true
  fi

  # Load economy tier (standard/lean/minimal) for tier-aware hook output.
  # Cached at SessionStart by project-config.sh into scope/.economy-tier.
  if [ -z "${SUPERCHARGER_TIER:-}" ]; then
    local tier_file="$HOME/.claude/supercharger/scope/.economy-tier"
    if [ -f "$tier_file" ]; then
      SUPERCHARGER_TIER=$(<"$tier_file")
    else
      SUPERCHARGER_TIER="standard"
    fi
    export SUPERCHARGER_TIER
  fi
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

  if [ "$profile" = "fast" ]; then
    case "$hook_name" in
      adaptive-economy|thinking-budget|rate-limit-advisor|\
      mcp-tracker|failure-tracker|session-checkpoint|\
      repetition-detector|context-advisor)
        return 0 ;;
    esac
  fi

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

# Per-session, per-hook dedup — saves tokens on repeated systemMessage emissions.
# Usage:
#   hook_already_emitted "<hook_name>" "<session_id>" "<message>" && exit 0
# TTL: 600s (10 min). Hashes stored in ~/.claude/supercharger/scope/.dedup-<sid>-<hook>
# Returns 0 (already emitted, skip) or 1 (new, proceed and record).
hook_already_emitted() {
  local hook_name="${1:-}" sid="${2:-}" msg="${3:-}"
  [ -z "$hook_name" ] && return 1
  [ -z "$sid" ] && return 1
  [ -z "$msg" ] && return 1
  # Test/CI escape hatch
  [ "${SUPERCHARGER_NO_DEDUP:-0}" = "1" ] && return 1

  local scope_dir="$HOME/.claude/supercharger/scope"
  local dedup_file="${scope_dir}/.dedup-${sid}-${hook_name}"
  local now hash
  hash=$(printf '%s' "$msg" | md5 -q 2>/dev/null || printf '%s' "$msg" | md5sum 2>/dev/null | cut -c1-32 || printf 'NOHASH')

  if [ -f "$dedup_file" ]; then
    now=$(date +%s)
    # Strip stale entries (>600s old) and check for our hash
    local kept="" stale_cutoff=$((now - 600))
    while IFS='|' read -r ts seen_hash; do
      [ -z "$ts" ] && continue
      [ "$ts" -lt "$stale_cutoff" ] && continue
      kept="${kept}${ts}|${seen_hash}"$'\n'
      if [ "$seen_hash" = "$hash" ]; then
        printf '%s' "$kept" > "$dedup_file"
        return 0
      fi
    done < "$dedup_file"
    printf '%s%s|%s\n' "$kept" "$now" "$hash" > "$dedup_file"
  else
    mkdir -p "$scope_dir" 2>/dev/null || true
    printf '%s|%s\n' "$(date +%s)" "$hash" > "$dedup_file" 2>/dev/null || true
  fi
  return 1
}

# Cache jq availability for this session — avoids repeated failed fork on jq-less systems
if [ -z "${_JQ_AVAILABLE+set}" ]; then
  command -v jq &>/dev/null && _JQ_AVAILABLE=1 || _JQ_AVAILABLE=0
  export _JQ_AVAILABLE
fi

# Default initialisation (no project dir yet — hooks should re-call after reading input)
init_hook_suppress
