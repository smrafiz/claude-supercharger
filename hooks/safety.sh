#!/usr/bin/env bash
set -euo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('input',{}).get('command',''))" 2>/dev/null || echo "")

if [ -z "$COMMAND" ]; then
  exit 0
fi

CMD="$COMMAND"
CMD=$(echo "$CMD" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
CMD=$(echo "$CMD" | sed 's/^\\//')
while echo "$CMD" | grep -qE '^(sudo|command|env)[[:space:]]+'; do
  CMD=$(echo "$CMD" | sed -E 's/^(sudo|command|env)[[:space:]]+//')
done
CMD=$(echo "$CMD" | tr -s ' ')

block() {
  echo "BLOCKED by Supercharger safety hook: $1" >&2
  echo "Command: $COMMAND" >&2
  exit 2
}

if echo "$CMD" | grep -qE '^rm[[:space:]]'; then
  has_recursive=false
  has_force=false

  set +e
  args="${CMD#rm }"

  if echo "$args" | grep -qE '(^|[[:space:]])-[a-zA-Z]*r[a-zA-Z]*([[:space:]]|$)' || \
     echo "$args" | grep -qE '(^|[[:space:]])--recursive([[:space:]]|$)'; then
    has_recursive=true
  fi

  if echo "$args" | grep -qE '(^|[[:space:]])-[a-zA-Z]*f[a-zA-Z]*([[:space:]]|$)' || \
     echo "$args" | grep -qE '(^|[[:space:]])--force([[:space:]]|$)'; then
    has_force=true
  fi
  set -e

  if $has_recursive && $has_force; then
    if echo "$args" | grep -qE '(^|[[:space:]])(\/[[:space:]]*$|\/\*|~|\$HOME|\.\.)([[:space:]]|$)'; then
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
  'truncate[[:space:]]+-s[[:space:]]*0'
  ':\(\)\{[[:space:]]*:\|:&[[:space:]]*\};:'
  'kill[[:space:]]+-9[[:space:]]+-1'
)

for pattern in "${DANGEROUS_PATTERNS[@]}"; do
  if echo "$CMD" | grep -qiE "$pattern"; then
    block "dangerous pattern: $pattern"
  fi
done

if echo "$CMD" | grep -qE '^mv[[:space:]]+(\/|~|\$HOME)[[:space:]]'; then
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
)

for pattern in "${CRED_PATTERNS[@]}"; do
  if echo "$CMD" | grep -qE "$pattern"; then
    block "potential credential in command — never embed secrets in commands"
  fi
done

# --- Unauthorized persistence ---
if echo "$CMD" | grep -qE '(crontab[[:space:]]+-e|crontab[[:space:]]+-)'; then
  block "cron job modification — agent should not create persistent scheduled tasks"
fi

if echo "$CMD" | grep -qE '(>>?[[:space:]]*(~|\$HOME)?/?\.(bashrc|zshrc|profile|bash_profile|zprofile))'; then
  block "shell profile modification — agent should not modify shell startup files"
fi

if echo "$CMD" | grep -qE 'ssh-keygen|ssh-add|ssh-copy-id'; then
  block "SSH key operation — agent should not manage SSH keys"
fi

# --- Self-modification prevention ---
if echo "$CMD" | grep -qE '(\.claude/settings\.json|\.claude/CLAUDE\.md)'; then
  if echo "$CMD" | grep -qE '(>|>>|sed|awk|tee|mv|cp|rm|cat.*>|python.*open|echo.*>)'; then
    block "self-modification — agent should not directly edit its own config files"
  fi
fi

# --- Production reads (warn only — exit 1, not exit 2) ---
if echo "$CMD" | grep -qE '(kubectl[[:space:]]+exec|docker[[:space:]]+exec).*prod'; then
  echo "WARNING: Production container access detected. Live credentials may leak into transcript." >&2
  exit 0
fi

exit 0
