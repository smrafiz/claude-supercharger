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
  'AKIA[0-9A-Z]{16}'
  'gh[ps]_[A-Za-z0-9_]{36,}'
  '(?i)api[_-]?key|api[_-]?secret|access[_-]?token'
  'Bearer [A-Za-z0-9._-]+'
  'BEGIN.{0,10}PRIVATE KEY'
  '://[^:@/\s]+:[^@/\s]+@'
  'sk_live_|pk_live_'
  'npm_[A-Za-z0-9]{36}'
  'eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}'
)

COMBINED_PATTERN=$(IFS='|'; echo "${SECRET_PATTERNS[*]}")

if printf '%s\n' "$OUTPUT" | LC_ALL=C grep -qE "$COMBINED_PATTERN"; then
  echo "[Supercharger] SECRET DETECTED in tool output — warning Claude" >&2
  python3 -c "
import json
msg = '[SECURITY] Tool output contains what appears to be a secret/credential. Do NOT repeat, log, or include this value in your response. Refer to it generically (e.g., \"the API key\") without showing the actual value.'
print(json.dumps({'additionalContext': msg}))
"
fi

exit 0
