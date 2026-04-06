#!/usr/bin/env bash
set -euo pipefail

COMMAND=$(python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('command',''))" 2>/dev/null || echo "")

if [ -z "$COMMAND" ]; then
  exit 0
fi

CMD="$COMMAND"
CMD=$(printf '%s\n' "$CMD" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
CMD=$(printf '%s\n' "$CMD" | sed 's/^\\//')
while printf '%s\n' "$CMD" | grep -qE '^(sudo|command|env)[[:space:]]+'; do
  CMD=$(printf '%s\n' "$CMD" | sed -E 's/^(sudo|command|env)[[:space:]]+//')
done
CMD=$(printf '%s\n' "$CMD" | tr -s ' ')

block() {
  echo "" >&2
  echo "Supercharger blocked this command." >&2
  echo "  Reason : $1" >&2
  echo "  Command: $COMMAND" >&2
  echo "  Tell me to confirm if you want to proceed anyway." >&2
  echo "" >&2
  exit 2
}

if printf '%s\n' "$CMD" | grep -qE '^rm[[:space:]]'; then
  has_recursive=false
  has_force=false

  set +e
  args="${CMD#rm }"

  if printf '%s\n' "$args" | grep -qE '(^|[[:space:]])-[a-zA-Z]*r[a-zA-Z]*([[:space:]]|$)' || \
     printf '%s\n' "$args" | grep -qE '(^|[[:space:]])--recursive([[:space:]]|$)'; then
    has_recursive=true
  fi

  if printf '%s\n' "$args" | grep -qE '(^|[[:space:]])-[a-zA-Z]*f[a-zA-Z]*([[:space:]]|$)' || \
     printf '%s\n' "$args" | grep -qE '(^|[[:space:]])--force([[:space:]]|$)'; then
    has_force=true
  fi
  set -e

  if $has_recursive && $has_force; then
    if printf '%s\n' "$args" | grep -qE '(^|[[:space:]])(\/[[:space:]]*$|\/\*|~|\$HOME|\.\.)([[:space:]]|$)'; then
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

for pattern in "${DANGEROUS_PATTERNS[@]}"; do
  if printf '%s\n' "$CMD" | LC_ALL=C grep -qiE "$pattern"; then
    block "dangerous pattern: $pattern"
  fi
done

if printf '%s\n' "$CMD" | grep -qE '^mv[[:space:]]+(\/|~|\$HOME)[[:space:]]'; then
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

for pattern in "${CRED_PATTERNS[@]}"; do
  if printf '%s\n' "$CMD" | LC_ALL=C grep -qE "$pattern"; then
    block "potential credential in command — never embed secrets in commands"
  fi
done

# --- Unauthorized persistence ---
if printf '%s\n' "$CMD" | grep -qE '(crontab[[:space:]]+-e|crontab[[:space:]]+-)'; then
  block "cron job modification — agent should not create persistent scheduled tasks"
fi

if printf '%s\n' "$CMD" | grep -qE '(>>?[[:space:]]*(~|\$HOME)?/?\.(bashrc|zshrc|profile|bash_profile|zprofile))'; then
  block "shell profile modification — agent should not modify shell startup files"
fi

if printf '%s\n' "$CMD" | grep -qE 'ssh-keygen|ssh-add|ssh-copy-id'; then
  block "SSH key operation — agent should not manage SSH keys"
fi

# --- Self-modification prevention ---
if printf '%s\n' "$CMD" | grep -qE '(\.claude/settings\.json|\.claude/CLAUDE\.md)'; then
  if printf '%s\n' "$CMD" | grep -qE '(>|>>|sed|awk|tee|mv|cp|rm|cat.*>|python.*open|echo.*>)'; then
    block "self-modification — agent should not directly edit its own config files"
  fi
fi

# --- Production reads (warn only — exit 1, not exit 2) ---
if printf '%s\n' "$CMD" | grep -qE '(kubectl[[:space:]]+exec|docker[[:space:]]+exec).*prod'; then
  echo "" >&2
  echo "Supercharger warning: Production container access detected." >&2
  echo "  Live credentials may appear in your conversation transcript." >&2
  echo "" >&2
  exit 0
fi

exit 0
