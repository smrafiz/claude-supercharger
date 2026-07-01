#!/usr/bin/env bash
# Claude Supercharger — Worktree* Discovery Hook
# Events: WorktreeCreate | WorktreeRemove  (Matcher: *)
#
# WorktreeCreate/WorktreeRemove are hook EVENTS Claude Code added in the v2.1.x
# series (they fire on git-worktree lifecycle, not as tool calls — v2.7.26 fixed
# a mis-wiring that had registered this on PreToolUse with a tool matcher, so it
# never fired). Their payload schemas are not yet fully documented (issue
# #36205). This hook is pure observation: it captures the payload to a local
# audit log so we can design proper safety guards (e.g. block worktree creation
# outside the project tree, prevent removal of dirty worktrees) once we know the
# real shape.
#
# Behavior: passthrough (exit 0). Never blocks.
# Storage: ~/.claude/supercharger/audit/worktree-payloads.jsonl  (capped at 10KB/entry)
# Disable: SUPERCHARGER_WORKTREE_DISCOVERY=0

set -euo pipefail
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HOOKS_DIR/lib-suppress.sh"

[ "${SUPERCHARGER_WORKTREE_DISCOVERY:-1}" = "0" ] && exit 0

_INPUT=$(cat)
PROJECT_DIR=$(printf '%s\n' "$_INPUT" | jq -r '.cwd // .workspace.current_dir // empty' 2>/dev/null || true); [ -z "$PROJECT_DIR" ] && PROJECT_DIR="$PWD"
init_hook_suppress "$PROJECT_DIR"
check_hook_disabled "worktree-discovery" && exit 0

AUDIT_DIR="$HOME/.claude/supercharger/audit"
mkdir -p "$AUDIT_DIR" 2>/dev/null || exit 0
LOG_FILE="$AUDIT_DIR/worktree-payloads.jsonl"

CAPPED=$(HOOK_INPUT="$_INPUT" python3 <<'PYEOF' 2>/dev/null
import json, os, sys, datetime
raw = os.environ.get('HOOK_INPUT', '')
try:
    data = json.loads(raw)
except Exception:
    print(json.dumps({"error": "parse_failed", "raw_size": len(raw)}))
    sys.exit(0)

def trunc(v, lim=2000):
    if isinstance(v, str) and len(v) > lim:
        return v[:lim] + f'...[{len(v)-lim}b truncated]'
    if isinstance(v, dict):
        return {k: trunc(x, lim) for k, x in v.items()}
    if isinstance(v, list):
        return [trunc(x, lim) for x in v[:20]]
    return v

# v2.7.26: these are EVENTS with an unknown payload shape — capture ALL
# top-level keys generically (not just tool_* fields) so the real schema is
# fully visible in the audit log.
known = {"hook_event_name", "session_id", "cwd"}
record = {
    "ts": datetime.datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ'),
    "hook_event_name": data.get("hook_event_name", ""),
    "session_id": data.get("session_id", ""),
    "cwd": data.get("cwd", ""),
    "keys": sorted(data.keys()),
    "extra": {k: trunc(v) for k, v in data.items() if k not in known},
}
print(json.dumps(record))
PYEOF
)
[ -z "$CAPPED" ] && exit 0
printf '%s\n' "$CAPPED" >> "$LOG_FILE" 2>/dev/null || true

echo "[Supercharger] worktree-discovery: logged payload to $LOG_FILE" >&2
exit 0
