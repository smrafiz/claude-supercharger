#!/usr/bin/env bash
# Claude Supercharger — Shared Notification Helper
# Sourced by notify.sh, notify-stop.sh, notify-permission.sh

# Resolve state/code roots for both installer and plugin runtimes (see lib-paths.sh).
. "${BASH_SOURCE[0]%/*}/lib-paths.sh" 2>/dev/null || true
: "${SUPERCHARGER_STATE:=${CLAUDE_PLUGIN_DATA:-$HOME/.claude/supercharger}}"
: "${SUPERCHARGER_HOME:=${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/supercharger}}"

SUPERCHARGER_DIR="$SUPERCHARGER_STATE"
SCOPE_DIR="$SUPERCHARGER_DIR/scope"

# Get git branch for notification title
_get_branch() {
  git branch --show-current 2>/dev/null || echo ""
}

# Configurable cooldown (default 15s). Optional 3rd arg = session id: when given,
# the cooldown stamp is per-session (2.21.15) so one session's notification
# doesn't suppress another's within the window. Omitted (e.g. the machine-wide
# idle ping) keeps the shared global stamp — backward compatible.
_cooldown_ok() {
  local key="$1"
  local cooldown="${2:-15}"
  local sid="${3:-}"
  local stamp="$SCOPE_DIR/.notify-ts-${key}${sid:+-$sid}"
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

# v2.26.49: is there a Windows host we can raise a toast on? Covers Git Bash /
# MSYS / Cygwin (OSTYPE) and WSL, where the kernel release string carries
# "microsoft" and powershell.exe is reachable through interop.
#
# Echoes a non-empty string when yes. Fork-free on the common path: OSTYPE is a
# shell variable, and the /proc read only happens on Linux.
_win_host() {
  case "$OSTYPE" in
    msys*|cygwin*|win32) printf 'win'; return 0 ;;
  esac
  [ -n "${WSL_DISTRO_NAME:-}" ] && { printf 'wsl'; return 0; }
  if [ -r /proc/sys/kernel/osrelease ]; then
    local rel; IFS= read -r rel < /proc/sys/kernel/osrelease || rel=""
    case "$rel" in *[Mm]icrosoft*) printf 'wsl'; return 0 ;; esac
  fi
  return 0
}

# Send notification with click-to-focus
_send_notification() {
  # v2.23.8: never emit a REAL desktop notification during test/CI runs. Hook
  # tests that exercise a block path (e.g. elicitation-guard) would otherwise pop
  # a live macOS/Linux notification on the developer's screen. The suite exports
  # SUPERCHARGER_NO_NOTIFY=1; the notify-helper's own tests, which assert on the
  # send path, mock osascript/notify-send and unset this var.
  [ -n "${SUPERCHARGER_NO_NOTIFY:-}" ] && return 0
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
  elif [ -n "$(_win_host)" ] && ! command -v notify-send >/dev/null 2>&1; then
    # v2.26.49 (WINDOWS-SUPPORT-PLAN G1): Git Bash / MSYS / Cygwin, and WSL with
    # no working notify-send. Until now these fell through to the bell, which is
    # the reported "no notifications on Windows/WSL" bug.
    #
    # Ordered AFTER the notify-send check so a WSL setup with WSLg keeps using the
    # native Linux path — powershell.exe interop is the fallback there, not the
    # default. On Git Bash notify-send does not exist, so this is simply the path.
    #
    # Text goes through the ENVIRONMENT and is read as $env:VAR inside PowerShell.
    # Never interpolate it into the command string: a branch name reaches here
    # (see the v2.6.72 AppleScript RCE), and PowerShell would expand $(...) and
    # backticks in a double-quoted literal exactly as bash did.
    local ps_body="$safe_msg"; [ -n "$safe_sub" ] && ps_body="${safe_sub} — ${safe_msg}"
    local ps_exe
    ps_exe=$(command -v powershell.exe 2>/dev/null || command -v pwsh.exe 2>/dev/null || command -v pwsh 2>/dev/null || true)
    if [ -n "$ps_exe" ]; then
      # Layered, each falling to the next: BurntToast (clean API, if installed) →
      # native WinRT toast (Win10+, no dependency) → bell. Every layer is wrapped
      # so a missing module or an older Windows never errors the hook.
      SC_NOTIFY_TITLE="$safe_title" SC_NOTIFY_MSG="$ps_body" \
        "$ps_exe" -NoProfile -NonInteractive -Command '
$t = $env:SC_NOTIFY_TITLE; $m = $env:SC_NOTIFY_MSG
if (Get-Module -ListAvailable -Name BurntToast) {
  Import-Module BurntToast -ErrorAction Stop
  New-BurntToastNotification -Text $t, $m
} else {
  [void][Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType=WindowsRuntime]
  $tpl = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent([Windows.UI.Notifications.ToastTemplateType]::ToastText02)
  $tx = $tpl.GetElementsByTagName("text")
  [void]$tx.Item(0).AppendChild($tpl.CreateTextNode($t))
  [void]$tx.Item(1).AppendChild($tpl.CreateTextNode($m))
  $toast = [Windows.UI.Notifications.ToastNotification]::new($tpl)
  [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier("Claude Supercharger").Show($toast)
}' 2>/dev/null || printf '\a'
    else
      printf '\a'
    fi
  elif command -v notify-send &>/dev/null; then
    # Linux notify-send has no subtitle tier — fold it into the body (\n works here)
    local ns_body="$safe_msg"; [ -n "$safe_sub" ] && ns_body="${safe_sub}"$'\n'"${safe_msg}"
    notify-send "$safe_title" "$ns_body" 2>/dev/null || true  # v2.6.77: use sanitized vars
  else
    printf '\a'
  fi
}
