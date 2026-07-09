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
  agent_id=$(printf '%s\n' "$input" | jq -r '.agent_id // empty' 2>/dev/null || true)
  [ -n "$agent_id" ] && return 0
  return 1
}

# Send notification with click-to-focus
_send_notification() {
  local title="$1"
  local msg="$2"
  local subtitle="${3:-}"   # v2.7.34: optional middle tier (title/subtitle/body)

  # A caller-supplied subtitle owns the context line; otherwise keep the legacy
  # behaviour of appending the git branch to the title.
  local branch
  branch=$(_get_branch)
  [ -z "$subtitle" ] && [ -n "$branch" ] && title="${title} [${branch}]"

  # Sanitize for osascript: strip backticks and $ first (shell-eval vectors
  # inside the -e argument since bash interprets the string BEFORE osascript
  # sees it), then escape backslashes and double-quotes for AppleScript.
  # v2.6.72: a branch name like `test`open /App/Calc.app`` triggered RCE
  # before the strip — sed only handled \ and " but bash still expanded ` and $.
  local safe_msg
  safe_msg=$(printf '%s' "$msg" | tr -d '`$' | sed "s/\\\\/\\\\\\\\/g; s/\"/\\\\\"/g" | head -c 200)
  local safe_title
  safe_title=$(printf '%s' "$title" | tr -d '`$' | sed "s/\\\\/\\\\\\\\/g; s/\"/\\\\\"/g")
  local safe_sub
  safe_sub=$(printf '%s' "$subtitle" | tr -d '`$' | sed "s/\\\\/\\\\\\\\/g; s/\"/\\\\\"/g" | head -c 120)

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
    # v2.7.33: transliterate to ASCII. AppleScript's `system attribute` reads env
    # vars as MacRoman, so UTF-8 punctuation/symbols get mojibake'd (— → ,Äî,
    # → → ,Üí). iconv //TRANSLIT maps them to ASCII (— → -, → → ->); tr drops any
    # leftover non-ASCII; fall back to the raw string if iconv is unavailable.
    # NOTE: iconv //TRANSLIT exits non-zero even when it transliterates fine, so
    # `|| true` is required — under a caller's `set -euo pipefail` the assignment
    # would otherwise abort the hook before it ever notifies.
    local ascii_msg ascii_title ascii_sub
    ascii_msg=$(printf '%s' "$safe_msg" | iconv -f UTF-8 -t ASCII//TRANSLIT 2>/dev/null | tr -cd '\11\12\15\40-\176' || true); [ -z "$ascii_msg" ] && ascii_msg="$safe_msg"
    ascii_title=$(printf '%s' "$safe_title" | iconv -f UTF-8 -t ASCII//TRANSLIT 2>/dev/null | tr -cd '\11\12\15\40-\176' || true); [ -z "$ascii_title" ] && ascii_title="$safe_title"
    ascii_sub=$(printf '%s' "$safe_sub" | iconv -f UTF-8 -t ASCII//TRANSLIT 2>/dev/null | tr -cd '\11\12\15\40-\176' || true); [ -z "$ascii_sub" ] && ascii_sub="$safe_sub"
    # Pass via env var to avoid shell re-interpretation of any surviving metachars
    if [ -n "$ascii_sub" ]; then
      SC_NOTIFY_MSG="$ascii_msg" SC_NOTIFY_TITLE="$ascii_title" SC_NOTIFY_SUB="$ascii_sub" \
        osascript -e 'display notification (system attribute "SC_NOTIFY_MSG") with title (system attribute "SC_NOTIFY_TITLE") subtitle (system attribute "SC_NOTIFY_SUB")' 2>/dev/null || true
    else
      SC_NOTIFY_MSG="$ascii_msg" SC_NOTIFY_TITLE="$ascii_title" \
        osascript -e 'display notification (system attribute "SC_NOTIFY_MSG") with title (system attribute "SC_NOTIFY_TITLE")' 2>/dev/null || true
    fi
  elif command -v notify-send &>/dev/null; then
    # Linux notify-send has no subtitle tier — fold it into the body (\n works here).
    # Checked before the Windows branch so a WSL user with a working notify-send
    # daemon keeps it; the PowerShell toast is only the fallback when it's absent.
    local ns_body="$safe_msg"; [ -n "$safe_sub" ] && ns_body="${safe_sub}"$'\n'"${safe_msg}"
    notify-send "$safe_title" "$ns_body" 2>/dev/null || true  # v2.6.77: use sanitized vars
  elif [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" ]] || grep -qiE '(microsoft|wsl)' /proc/version 2>/dev/null; then
    # v2.9.3: Windows (Git Bash/MSYS/Cygwin) or WSL without notify-send — reach the
    # Windows toast via PowerShell. On WSL this uses the powershell.exe interop
    # bridge; on Git Bash it's the native shell. Layered fallback: BurntToast toast
    # -> NotifyIcon balloon -> bell. Strings pass through env vars so branch/message
    # content is never eval-interpolated by PowerShell (same defense as osascript).
    local ps_exe=""
    local c
    for c in powershell.exe pwsh.exe pwsh powershell; do
      command -v "$c" &>/dev/null && { ps_exe="$c"; break; }
    done
    if [ -n "$ps_exe" ]; then
      local win_body="$safe_msg"; [ -n "$safe_sub" ] && win_body="${safe_sub} - ${safe_msg}"
      SC_NOTIFY_TITLE="$safe_title" SC_NOTIFY_BODY="$win_body" "$ps_exe" -NoProfile -NonInteractive -Command '
        $t = $env:SC_NOTIFY_TITLE; $b = $env:SC_NOTIFY_BODY
        if (Get-Module -ListAvailable -Name BurntToast) {
          Import-Module BurntToast; New-BurntToastNotification -Text $t, $b
        } else {
          Add-Type -AssemblyName System.Windows.Forms
          $n = New-Object System.Windows.Forms.NotifyIcon
          $n.Icon = [System.Drawing.SystemIcons]::Information
          $n.Visible = $true
          $n.ShowBalloonTip(5000, $t, $b, [System.Windows.Forms.ToolTipIcon]::Info)
        }
      ' 2>/dev/null || printf '\a'
    else
      printf '\a'
    fi
  else
    printf '\a'
  fi
}
