#!/usr/bin/env bash
set -euo pipefail

_INPUT=$(cat)
COMMAND=$(printf '%s\n' "$_INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
if [ -z "$COMMAND" ]; then
  COMMAND=$(printf '%s\n' "$_INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('command',''))" 2>/dev/null || echo "")
fi

if [ -z "$COMMAND" ]; then
  exit 0
fi

source "$(dirname "${BASH_SOURCE[0]}")/cmd-normalize.sh"
CMD=$(normalize_cmd "$COMMAND")

block() {
  echo "" >&2
  echo "Supercharger blocked this command." >&2
  echo "  Reason : $1" >&2
  echo "  Command: $COMMAND" >&2
  echo "  This command is permanently blocked. Run it in your terminal directly if needed." >&2
  echo "" >&2
  # Log for learning — future sessions will know to avoid this pattern
  local blocks_log="$HOME/.claude/supercharger/scope/.blocked-commands"
  mkdir -p "$(dirname "$blocks_log")" 2>/dev/null || true
  printf '[%s] %s — %s\n' "$(date '+%Y-%m-%d %H:%M')" "$1" "$COMMAND" >> "$blocks_log" 2>/dev/null || true
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$1"
  exit 2
}

if [[ "$CMD" =~ ^rm[[:space:]] ]]; then
  has_recursive=false
  has_force=false

  args="${CMD#rm }"

  if [[ "$args" =~ (^|[[:space:]])-[a-zA-Z]*r[a-zA-Z]*([[:space:]]|$) ]] || \
     [[ "$args" =~ (^|[[:space:]])--recursive([[:space:]]|$) ]]; then
    has_recursive=true
  fi

  if [[ "$args" =~ (^|[[:space:]])-[a-zA-Z]*f[a-zA-Z]*([[:space:]]|$) ]] || \
     [[ "$args" =~ (^|[[:space:]])--force([[:space:]]|$) ]]; then
    has_force=true
  fi

  if $has_recursive && $has_force; then
    if [[ "$args" =~ (^|[[:space:]])(\/[[:space:]]*$|\/\*|~|\$HOME|\.\.)([[:space:]]|$) ]]; then
      block "recursive force rm on dangerous target"
    fi
  fi
fi

DANGEROUS_PATTERNS=(
  'DROP[[:space:]]+TABLE'
  'DROP[[:space:]]+DATABASE'
  'chmod[[:space:]]+(-R[[:space:]]+)?777'
  'mkfs\.'
  'dd[[:space:]]+if='
  '>[[:space:]]*/dev/sd'
  'curl.*\|.*bash'
  'curl.*\|.*sh'
  'wget.*\|.*bash'
  'wget.*\|.*sh'
  '\|[[:space:]]*(bash|sh|zsh|dash)([[:space:]]|$)'
  'truncate[[:space:]]+-s[[:space:]]*0'
  ':\(\)\{[[:space:]]*:\|:&[[:space:]]*\};:'
  'kill[[:space:]]+-9[[:space:]]+-1'
  '(^|;|&&|\|\|)[[:space:]]*(bash|sh|zsh)[[:space:]]+-c[[:space:]]'
  '(^|;|&&|\|\|)[[:space:]]*eval[[:space:]]+'
  '(^|;|&&|\|\|)[[:space:]]*source[[:space:]]+/dev/(tcp|udp)/'
  'base64.*\|.*(bash|sh|zsh)'
  '<<<.*\|.*(bash|sh|zsh)'
)

JOINED_DANGEROUS=$(IFS='|'; echo "${DANGEROUS_PATTERNS[*]}")
if printf '%s\n' "$CMD" | LC_ALL=C grep -qiE "$JOINED_DANGEROUS"; then
  for pattern in "${DANGEROUS_PATTERNS[@]}"; do
    if printf '%s\n' "$CMD" | LC_ALL=C grep -qiE "$pattern"; then
      block "dangerous pattern: $pattern"
    fi
  done
fi

if [[ "$CMD" =~ ^mv[[:space:]]+(\/|~|\$HOME)[[:space:]] ]]; then
  block "mv from root or home directory"
fi

# --- Credential leakage ---
CRED_PATTERNS=(
  '[Aa][Pp][Ii][_-]?[Kk][Ee][Yy][[:space:]]*='
  '[Ss][Ee][Cc][Rr][Ee][Tt][_-]?[Kk][Ee][Yy][[:space:]]*='
  '[Aa][Cc][Cc][Ee][Ss][Ss][_-]?[Tt][Oo][Kk][Ee][Nn][[:space:]]*='
  'AKIA[0-9A-Z]{16}'
  'ghp_[0-9a-zA-Z]{36}'
  'sk-[0-9a-zA-Z]{48}'
  'AIza[0-9A-Za-z_-]{35}'
  'sk_live_[0-9a-zA-Z]{24}'
  'pk_live_[0-9a-zA-Z]{24}'
  'npm_[0-9a-zA-Z]{36}'
  'pypi-[0-9a-zA-Z_-]{16,}'
  '[Pp][Aa][Ss][Ss][Ww][Oo][Rr][Dd][[:space:]]*='
  'DB_PASSWORD[[:space:]]*='
  'MYSQL_ROOT_PASSWORD[[:space:]]*='
  '-----BEGIN[[:space:]]+(RSA|EC|DSA|OPENSSH)?[[:space:]]*PRIVATE[[:space:]]+KEY-----'
  'eyJ[0-9a-zA-Z_-]{10,}\.[0-9a-zA-Z_-]{10,}\.'
)

JOINED_CRED=$(IFS='|'; echo "${CRED_PATTERNS[*]}")
if printf '%s\n' "$CMD" | LC_ALL=C grep -qE "$JOINED_CRED"; then
  block "potential credential in command — never embed secrets in commands"
fi

# --- Unauthorized persistence ---
if [[ "$CMD" =~ (crontab[[:space:]]+-e|crontab[[:space:]]+-) ]]; then
  block "cron job modification — agent should not create persistent scheduled tasks"
fi

if [[ "$CMD" =~ (>>?[[:space:]]*(~|\$HOME)?/?\.(bashrc|zshrc|profile|bash_profile|zprofile)) ]]; then
  block "shell profile modification — agent should not modify shell startup files"
fi

if [[ "$CMD" =~ ssh-keygen|ssh-add|ssh-copy-id ]]; then
  block "SSH key operation — agent should not manage SSH keys"
fi

# --- Clipboard exfiltration ---
if [[ "$CMD" =~ (pbpaste|pbcopy|xclip|xsel|wl-paste|wl-copy) ]]; then
  block "clipboard access — agent should not read or write clipboard"
fi

# --- Sensitive app data paths ---
if [[ "$CMD" =~ (Application[[:space:]]+Support/(Google/Chrome|Arc|Firefox|BraveSoftware|Microsoft[[:space:]]+Edge)/|/Cookies|/Login[[:space:]]+Data|/History) ]]; then
  block "browser data access — agent should not read browser cookies, passwords, or history"
fi

if [[ "$CMD" =~ (Library/Keychains|Library/Messages|Signal/sql|1Password|gnome-keyring|\.password-store) ]]; then
  block "sensitive app data — agent should not access keychains, messages, or password managers"
fi

if [[ "$CMD" =~ (\.(bash_history|zsh_history|python_history|psql_history|mysql_history|node_repl_history)) ]]; then
  block "shell history access — may contain credentials or sensitive commands"
fi

# --- Self-modification prevention ---
if [[ "$CMD" =~ (\.claude/settings\.json|\.claude/CLAUDE\.md) ]]; then
  if [[ "$CMD" =~ (>|>>|sed|awk|tee|mv|cp|rm|cat.*>|python.*open|echo.*>) ]]; then
    block "self-modification — agent should not directly edit its own config files"
  fi
fi

# --- Production reads (warn only — exit 1, not exit 2) ---
if [[ "$CMD" =~ (kubectl[[:space:]]+exec|docker[[:space:]]+exec).*prod ]]; then
  echo "" >&2
  echo "Supercharger warning: Production container access detected." >&2
  echo "  Live credentials may appear in your conversation transcript." >&2
  echo "" >&2
  exit 0
fi

exit 0
