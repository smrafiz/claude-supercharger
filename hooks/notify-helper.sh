#!/usr/bin/env bash
# Claude Supercharger — Shared Notification Helper
# Sourced by notify.sh, notify-stop.sh, notify-permission.sh

SUPERCHARGER_DIR="$HOME/.claude/supercharger"
SCOPE_DIR="$SUPERCHARGER_DIR/scope"

# Get git branch for notification title
_get_branch() {
  git branch --show-current 2>/dev/null || echo ""
}

# Configurable cooldown (default 15s)
_cooldown_ok() {
  local key="$1"
  local cooldown="${2:-15}"
  local stamp="$SCOPE_DIR/.notify-ts-${key}"
  if [ -f "$stamp" ]; then
    local last_ts
    last_ts=$(cat "$stamp" 2>/dev/null || echo "0")
    [ -z "$last_ts" ] && last_ts=0
    local now diff
    now=$(date +%s)
    diff=$((now - last_ts))
    [ "$diff" -lt "$cooldown" ] && return 1
  fi
  mkdir -p "$SCOPE_DIR" 2>/dev/null || true
  date +%s > "$stamp" 2>/dev/null || true
  return 0
}

# Check if running inside a subagent
_is_subagent() {
  local input="$1"
  local agent_id
  agent_id=$(printf '%s\n' "$input" | jq -r '.agent_id // empty' 2>/dev/null)
  [ -n "$agent_id" ] && return 0
  return 1
}

# Send notification with click-to-focus
_send_notification() {
  local title="$1"
  local msg="$2"

  # Append git branch to title
  local branch
  branch=$(_get_branch)
  [ -n "$branch" ] && title="${title} [${branch}]"

  # Sanitize for osascript
  local safe_msg
  safe_msg=$(printf '%s' "$msg" | sed "s/\\\\/\\\\\\\\/g; s/\"/\\\\\"/g" | head -c 200)
  local safe_title
  safe_title=$(printf '%s' "$title" | sed "s/\\\\/\\\\\\\\/g; s/\"/\\\\\"/g")

  if [ -f "$SUPERCHARGER_DIR/.sound-only-notify" ]; then
    printf '\a'
  elif [[ "$OSTYPE" == "darwin"* ]]; then
    # Notification with click-to-focus: activate the terminal app
    local term_app="${TERM_PROGRAM:-Terminal}"
    case "$term_app" in
      WarpTerminal) term_app="Warp" ;;
      Apple_Terminal) term_app="Terminal" ;;
      vscode) term_app="Visual Studio Code" ;;
    esac
    osascript -e "display notification \"$safe_msg\" with title \"$safe_title\"" 2>/dev/null || true
  elif command -v notify-send &>/dev/null; then
    notify-send "$title" "$msg" 2>/dev/null || true
  else
    printf '\a'
  fi
}
