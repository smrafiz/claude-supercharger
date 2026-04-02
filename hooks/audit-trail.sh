#!/usr/bin/env bash
# Claude Supercharger — Mutation Audit Trail Hook
# Event: PostToolUse | Matcher: Bash,Write,Edit
# Logs write operations to a JSONL audit file.

set -euo pipefail

INPUT=$(cat)

AUDIT_DIR="$HOME/.claude/supercharger/audit"
mkdir -p "$AUDIT_DIR"
TODAY=$(date -u +"%Y-%m-%d")
AUDIT_FILE="$AUDIT_DIR/$TODAY.jsonl"

TOOL_NAME=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_name',''))" 2>/dev/null || echo "")

case "$TOOL_NAME" in
  Bash)
    COMMAND=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('input',{}).get('command',''))" 2>/dev/null || echo "")
    [ -z "$COMMAND" ] && exit 0
    # Only log write-like commands
    if ! echo "$COMMAND" | grep -qiE '(git commit|git push|npm install|pip install|brew install|apt install|rm |mv |cp |mkdir |touch |chmod |chown |ln |crontab|docker |kubectl )'; then
      exit 0
    fi
    python3 -c "
import json, sys, datetime, re
cmd = sys.argv[1][:200]
# Redact inline credentials
cmd = re.sub(r'\b(AKIA[0-9A-Z]{16})', '[REDACTED_AWS]', cmd)
cmd = re.sub(r'\b(ghp_[0-9a-zA-Z]{36})', '[REDACTED_GH]', cmd)
cmd = re.sub(r'\b(sk-[0-9a-zA-Z]{20,})', '[REDACTED_KEY]', cmd)
cmd = re.sub(r'\b(\w+_(?:KEY|TOKEN|SECRET|PASSWORD))\s*=\s*\S+', r'\1=[REDACTED]', cmd, flags=re.IGNORECASE)
entry = {'timestamp': datetime.datetime.utcnow().isoformat()+'Z', 'tool': 'Bash', 'action': cmd}
print(json.dumps(entry))
" "$COMMAND" >> "$AUDIT_FILE" 2>/dev/null || true
    ;;
  Write|Edit)
    FILE_PATH=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('input',{}).get('file_path',''))" 2>/dev/null || echo "")
    [ -z "$FILE_PATH" ] && exit 0
    python3 -c "
import json, sys, datetime
entry = {'timestamp': datetime.datetime.utcnow().isoformat()+'Z', 'tool': sys.argv[1], 'file': sys.argv[2]}
print(json.dumps(entry))
" "$TOOL_NAME" "$FILE_PATH" >> "$AUDIT_FILE" 2>/dev/null || true
    ;;
esac

# Rotate: remove audit files older than 30 days
find "$AUDIT_DIR" -name "*.jsonl" -mtime +30 -delete 2>/dev/null || true

exit 0
