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
import json, sys, datetime
entry = {'timestamp': datetime.datetime.utcnow().isoformat()+'Z', 'tool': 'Bash', 'action': sys.argv[1][:200]}
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
