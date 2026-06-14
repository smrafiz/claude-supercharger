#!/usr/bin/env bash
# Claude Supercharger — MessageDisplay Discovery Hook
# Event: MessageDisplay | Matcher: *
#
# MessageDisplay is a Claude Code event (added in late-May 2026 builds) that
# lets hooks transform or hide assistant message text as it is rendered. This
# is a new control surface: a malicious project-level hook can silently rewrite
# what the user sees, hiding prompt-injection effects or fabricating output.
#
# Before we ship a real defensive hook (e.g. warn on rewrite from foreign
# hooks, block tag-stripping that hides safety markers), we need the payload
# shape: message text length, message_id linkage, hookSpecificOutput keys.
#
# Behavior: passthrough (exit 0). Never blocks, never rewrites.
# Storage: ~/.claude/supercharger/audit/messagedisplay-payloads.jsonl
# Disable: SUPERCHARGER_MESSAGEDISPLAY_DISCOVERY=0
#
# To keep the log small, we record metadata only — never the message body.

set -euo pipefail
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HOOKS_DIR/lib-suppress.sh"

[ "${SUPERCHARGER_MESSAGEDISPLAY_DISCOVERY:-1}" = "0" ] && exit 0

_INPUT=$(cat)
PROJECT_DIR=$(printf '%s\n' "$_INPUT" | jq -r '.cwd // empty' 2>/dev/null); [ -z "$PROJECT_DIR" ] && PROJECT_DIR="$PWD"
init_hook_suppress "$PROJECT_DIR"
check_hook_disabled "messagedisplay-discovery" && exit 0

AUDIT_DIR="$HOME/.claude/supercharger/audit"
mkdir -p "$AUDIT_DIR" 2>/dev/null || exit 0
LOG_FILE="$AUDIT_DIR/messagedisplay-payloads.jsonl"

CAPPED=$(HOOK_INPUT="$_INPUT" python3 <<'PYEOF' 2>/dev/null
import json, os, sys, datetime
raw = os.environ.get('HOOK_INPUT', '')
try:
    data = json.loads(raw)
except Exception:
    print(json.dumps({"error": "parse_failed", "raw_size": len(raw)}))
    sys.exit(0)

# Record metadata only — message bodies are sensitive and large.
def length_of(v):
    if isinstance(v, str):
        return len(v)
    if isinstance(v, (dict, list)):
        try:
            return len(json.dumps(v))
        except Exception:
            return -1
    return None

record = {
    "ts": datetime.datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ'),
    "hook_event_name": data.get("hook_event_name", ""),
    "session_id": data.get("session_id", ""),
    "message_id": data.get("message_id", "") or data.get("messageId", ""),
    "_top_keys": sorted(data.keys()),
    "_field_sizes": {k: length_of(v) for k, v in data.items() if k not in ("session_id", "hook_event_name", "cwd")},
}
print(json.dumps(record))
PYEOF
)
[ -z "$CAPPED" ] && exit 0
printf '%s\n' "$CAPPED" >> "$LOG_FILE" 2>/dev/null || true

echo "[Supercharger] messagedisplay-discovery: metadata logged to $LOG_FILE" >&2
exit 0
