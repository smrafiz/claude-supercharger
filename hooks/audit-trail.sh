#!/usr/bin/env bash
# Claude Supercharger — Mutation Audit Trail Hook
# Event: PostToolUse | Matcher: Bash,Write,Edit
# Logs write operations to a JSONL audit file.

set -euo pipefail

_INPUT=$(cat)

AUDIT_DIR="$HOME/.claude/supercharger/audit"
mkdir -p "$AUDIT_DIR"
TODAY=$(date -u +"%Y-%m-%d")
AUDIT_FILE="$AUDIT_DIR/$TODAY.jsonl"

TOOL_NAME=$(printf '%s\n' "$_INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_name',''))" 2>/dev/null || echo "")

case "$TOOL_NAME" in
  Bash)
    COMMAND=$(printf '%s\n' "$_INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('command',''))" 2>/dev/null || echo "")
    [ -z "$COMMAND" ] && exit 0
    # Only log write-like commands
    if ! printf '%s\n' "$COMMAND" | grep -qiE '(git commit|git push|npm install|pip install|brew install|apt install|rm |mv |cp |mkdir |touch |chmod |chown |ln |crontab|docker |kubectl )'; then
      exit 0
    fi
    python3 -c "
import json, sys, datetime, re
cmd = sys.argv[1][:200]
# Redact inline credentials — mirrors safety.sh CRED_PATTERNS
cmd = re.sub(r'\bAKIA[0-9A-Z]{16}\b', '[REDACTED_AWS]', cmd)
cmd = re.sub(r'\bghp_[0-9a-zA-Z]{36}\b', '[REDACTED_GH]', cmd)
cmd = re.sub(r'\bsk-[0-9a-zA-Z]{20,}\b', '[REDACTED_KEY]', cmd)
cmd = re.sub(r'\bAIza[0-9A-Za-z_-]{35}\b', '[REDACTED_GOOG]', cmd)
cmd = re.sub(r'\bsk_live_[0-9a-zA-Z]{24}\b', '[REDACTED_STRIPE]', cmd)
cmd = re.sub(r'\bpk_live_[0-9a-zA-Z]{24}\b', '[REDACTED_STRIPE]', cmd)
cmd = re.sub(r'\bnpm_[0-9a-zA-Z]{36}\b', '[REDACTED_NPM]', cmd)
cmd = re.sub(r'\bpypi-[0-9a-zA-Z_-]{16,}\b', '[REDACTED_PYPI]', cmd)
cmd = re.sub(r'eyJ[0-9a-zA-Z_-]{10,}\.[0-9a-zA-Z_-]{10,}\.', '[REDACTED_JWT]', cmd)
cmd = re.sub(r'-----BEGIN\s*(RSA|EC|DSA|OPENSSH)?\s*PRIVATE KEY-----', '[REDACTED_PRIVKEY]', cmd)
cmd = re.sub(r'(?i)(https?|ftp)://[^:@/\s]+:[^@/\s]+@', r'\1://[REDACTED]@', cmd)
cmd = re.sub(r'(?i)\bBearer\s+[0-9a-zA-Z\-_.~+/]+=*\b', 'Bearer [REDACTED]', cmd)
cmd = re.sub(r'\b(\w+_(?:KEY|TOKEN|SECRET|PASSWORD|API_KEY))\s*=\s*\S+', r'\1=[REDACTED]', cmd, flags=re.IGNORECASE)
cmd = re.sub(r'(?i)\b(api[_-]?key|secret[_-]?key|access[_-]?token|password|db_password|mysql_root_password)\s*=\s*\S+', r'\1=[REDACTED]', cmd)
entry = {'timestamp': datetime.datetime.now(tz=datetime.timezone.utc).isoformat().replace('+00:00','Z'), 'tool': 'Bash', 'action': cmd}
print(json.dumps(entry))
" "$COMMAND" >> "$AUDIT_FILE" 2>/dev/null || true
    ;;
  Write|Edit)
    FILE_PATH=$(printf '%s\n' "$_INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('file_path',''))" 2>/dev/null || echo "")
    [ -z "$FILE_PATH" ] && exit 0
    python3 -c "
import json, sys, datetime
entry = {'timestamp': datetime.datetime.now(tz=datetime.timezone.utc).isoformat().replace('+00:00','Z'), 'tool': sys.argv[1], 'file': sys.argv[2]}
print(json.dumps(entry))
" "$TOOL_NAME" "$FILE_PATH" >> "$AUDIT_FILE" 2>/dev/null || true
    ;;
esac

# Rotate: remove audit files older than 30 days (at most once per day)
ROTATION_CHECK="$AUDIT_DIR/.last-rotation"
NOW=$(date +%s)
LAST_ROTATION=$(cat "$ROTATION_CHECK" 2>/dev/null || echo "0")
[ -z "$LAST_ROTATION" ] && LAST_ROTATION=0
if (( NOW - LAST_ROTATION > 86400 )); then
  find "$AUDIT_DIR" -name "*.jsonl" -mtime +30 -delete 2>/dev/null || true
  echo "$NOW" > "$ROTATION_CHECK"
fi

exit 0
