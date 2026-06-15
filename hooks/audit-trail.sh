#!/usr/bin/env bash
# Claude Supercharger — Mutation Audit Trail Hook
# Event: PostToolUse | Matcher: Bash,Write,Edit
# Logs write operations to a JSONL audit file.

set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib-timing.sh"

_INPUT=$(cat)

AUDIT_DIR="$HOME/.claude/supercharger/audit"
mkdir -p "$AUDIT_DIR"
TODAY=$(date -u +"%Y-%m-%d")
AUDIT_FILE="$AUDIT_DIR/$TODAY.jsonl"

# v2.6.18: bash fast-path + single-fork consolidation. Was 3 python3 forks
# (tool_name parse, command/file_path parse, JSONL write). Now: bash case on
# raw stdin pre-filters Bash to write-like verbs (skipping the python parse
# entirely for read-only commands like `ls`, `git log`), then a single python3
# heredoc does parse + redact + write. Median 70ms → ~20ms on read-only Bash
# (fast path), ~50ms on write-like Bash (was 70ms). Fires on every Write/Edit/
# Bash PostToolUse so the savings compound.
case "$_INPUT" in
  *'"tool_name":"Write"'*|*'"tool_name":"Edit"'*) ;;
  *'"tool_name":"Bash"'*)
    case "$_INPUT" in
      *'git commit'*|*'git push'*|*'npm install'*|*'pip install'*|*'brew install'*|*'apt install'*|*'apt-get install'*|\
      *'rm '*|*'mv '*|*'cp '*|*'mkdir '*|*'touch '*|*'chmod '*|*'chown '*|*'ln '*|*'crontab'*|*'docker '*|*'kubectl '*) ;;
      *) exit 0 ;;
    esac
    ;;
  *) exit 0 ;;
esac

HOOK_INPUT="$_INPUT" AUDIT_FILE="$AUDIT_FILE" python3 <<'PYEOF' 2>/dev/null || true
import json, os, sys, datetime, re

raw = os.environ.get('HOOK_INPUT', '')
audit_file = os.environ.get('AUDIT_FILE', '')

try:
    data = json.loads(raw)
except Exception:
    sys.exit(0)

tool = data.get('tool_name') or ''
tool_input = data.get('tool_input') or {}
entry = None

if tool == 'Bash':
    cmd = (tool_input.get('command') or '')[:200]
    if not cmd:
        sys.exit(0)
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
    entry = {'tool': 'Bash', 'action': cmd}
elif tool in ('Write', 'Edit'):
    path = tool_input.get('file_path') or ''
    if not path:
        sys.exit(0)
    entry = {'tool': tool, 'file': path}

if entry is None:
    sys.exit(0)

entry['timestamp'] = datetime.datetime.now(tz=datetime.timezone.utc).isoformat().replace('+00:00', 'Z')
# move timestamp to front for readability
ordered = {'timestamp': entry.pop('timestamp')}
ordered.update(entry)

try:
    with open(audit_file, 'a') as f:
        f.write(json.dumps(ordered) + '\n')
except Exception:
    pass
PYEOF

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
