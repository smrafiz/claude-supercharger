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

smart_approve_verdict() {
  local input="$1"
  local tool_name project_dir file_path abs_path command agent_id

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
