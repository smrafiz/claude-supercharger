#!/usr/bin/env bash
# Claude Supercharger — Output Secrets Scanner Hook
# Event: PostToolUse | Matcher: Bash,Read
# Scans tool output for leaked secrets and warns Claude not to repeat them.

set -euo pipefail

INPUT=$(cat)

OUTPUT=$(printf '%s\n' "$INPUT" | jq -r '.tool_response.output // empty' 2>/dev/null)
if [ -z "$OUTPUT" ]; then
  OUTPUT=$(printf '%s\n' "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_response',{}).get('output',''))" 2>/dev/null || echo "")
fi

[ -z "$OUTPUT" ] && exit 0
[ "${#OUTPUT}" -lt 10 ] && exit 0

SECRET_PATTERNS=(
  # AWS
  'AKIA[0-9A-Z]{16}'
  'ASIA[0-9A-Z]{16}'
  # GitHub
  'gh[opsu]_[A-Za-z0-9_]{36,}'
  # Generic
  '(?i)api[_-]?key|api[_-]?secret|access[_-]?token'
  'Bearer [A-Za-z0-9._-]+'
  # Private keys
  'BEGIN.{0,10}PRIVATE KEY'
  # URLs with embedded credentials
  '://[^:@/\s]+:[^@/\s]+@'
  # Stripe
  'sk_live_[0-9a-zA-Z]{24}'
  'rk_live_[0-9a-zA-Z]{24}'
  'pk_live_[0-9a-zA-Z]{24}'
  # npm
  'npm_[A-Za-z0-9]{36}'
  # JWTs
  'eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}'
  # OpenAI
  'sk-[A-Za-z0-9]{20,}'
  # Slack
  'xox[baprs]-[0-9A-Za-z-]{10,}'
  # HuggingFace
  'hf_[A-Za-z0-9]{30,}'
  # GCP service account
  '"private_key":\s*"-----BEGIN'
  # Azure storage
  'AccountKey=[A-Za-z0-9+/]{60,}='
  # Twilio
  'SK[0-9a-f]{32}'
  # SendGrid
  'SG\.[A-Za-z0-9_-]{22,}\.[A-Za-z0-9_-]{43,}'
)

COMBINED_PATTERN=$(IFS='|'; echo "${SECRET_PATTERNS[*]}")

if printf '%s\n' "$OUTPUT" | LC_ALL=C grep -qE "$COMBINED_PATTERN"; then
  echo "[Supercharger] SECRET DETECTED in tool output — warning Claude" >&2
  python3 -c "
import json
msg = '[SECURITY] Tool output contains what appears to be a secret/credential. Do NOT repeat, log, or include this value in your response. Refer to it generically (e.g., \"the API key\") without showing the actual value.'
print(json.dumps({'systemMessage': msg}))
"
  # Signal statusline: scan alert
  SCOPE_DIR="$HOME/.claude/supercharger/scope"
  mkdir -p "$SCOPE_DIR"
  echo "secrets" > "$SCOPE_DIR/.scan-alert" 2>/dev/null || true
  exit 2
fi

exit 0
