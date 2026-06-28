#!/usr/bin/env bash
# Claude Supercharger — Tool Call Limiter
# Event: PreToolUse | Matcher: (none)
# Counts tool calls per session. Warns at 80%, blocks at cap.
#
# Configure (pick one):
#   env var:           SESSION_MAX_TOOL_CALLS=100
#   .supercharger.json: { "maxToolCalls": 100 }
#
# No limit is enforced if neither is set.
# Session resets when CLAUDE_SESSION_ID changes or a new day begins.

set -euo pipefail
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh"
# shellcheck source=hooks/lib-project-root.sh
. "$HOOKS_DIR/lib-project-root.sh"
check_hook_disabled "tool-call-limiter" && exit 0

_INPUT=$(cat)

# ── Resolve cap ───────────────────────────────────────────────────────────────
CAP=""
if [ -n "${SESSION_MAX_TOOL_CALLS:-}" ]; then
  CAP="$SESSION_MAX_TOOL_CALLS"
else
  PROJECT_DIR=$(printf '%s\n' "$_INPUT" | jq -r '.cwd // .workspace.current_dir // empty' 2>/dev/null || true)
  [ -z "$PROJECT_DIR" ] && PROJECT_DIR="$PWD"
  # v2.6.36: walk from main worktree root if PROJECT_DIR is a linked worktree
  SEARCH_DIR=$(_resolve_project_root "$PROJECT_DIR")
  for _ in 1 2 3 4 5; do
    if [ -f "$SEARCH_DIR/.supercharger.json" ]; then
      CAP=$(python3 -c "
import json
try:
    with open('$SEARCH_DIR/.supercharger.json') as f:
        d = json.load(f)
    v = d.get('maxToolCalls', '')
    print(str(int(v)) if v else '')
except Exception:
    print('')
" 2>/dev/null || echo "")
      break
    fi
    PARENT=$(dirname "$SEARCH_DIR")
    [ "$PARENT" = "$SEARCH_DIR" ] && break
    SEARCH_DIR="$PARENT"
  done
fi

[ -z "$CAP" ] && exit 0

# ── Session scoping ───────────────────────────────────────────────────────────
SCOPE_DIR="$HOME/.claude/supercharger/scope"
mkdir -p "$SCOPE_DIR"

# Use CLAUDE_SESSION_ID if available; fall back to calendar date (daily reset)
SESSION_KEY="${CLAUDE_SESSION_ID:-$(date +%Y%m%d)}"
COUNTER_FILE="$SCOPE_DIR/.tool-calls-${SESSION_KEY}"

# ── Increment counter (atomic) ────────────────────────────────────────────────
CURRENT=0
[ -f "$COUNTER_FILE" ] && CURRENT=$(cat "$COUNTER_FILE" 2>/dev/null || echo 0)
NEW=$((CURRENT + 1))
echo "$NEW" > "$COUNTER_FILE"

# ── Read-only bypass — never block reads ─────────────────────────────────────
TOOL_NAME=$(printf '%s\n' "$_INPUT" | jq -r '.tool_name // empty' 2>/dev/null || true)
READ_ONLY_TOOLS="Read Glob Grep"
if printf ' %s ' $READ_ONLY_TOOLS | grep -q " $TOOL_NAME "; then
  exit 0
fi

# ── Evaluate thresholds ───────────────────────────────────────────────────────
# v2.7.3: was a python3 fork for pure integer arithmetic (count>cap, pct>=80) on
# every capped tool call. Bash $(()) does it natively — drops ~30ms/call. CAP is
# already numeric here (env var or python-validated int); guard defensively so a
# junk SESSION_MAX_TOOL_CALLS can't crash the arithmetic under set -e.
case "$CAP" in ''|*[!0-9]*|0) exit 0 ;; esac
PCT=$(( NEW * 100 / CAP ))

if [ "$NEW" -gt "$CAP" ]; then
  REASON="Tool call limit reached: $NEW calls this session (cap: $CAP). Start a new session or raise SESSION_MAX_TOOL_CALLS."
  echo "[Supercharger] tool-call-limiter: BLOCKING — $REASON" >&2
  RSN=$(printf '%s' "$REASON" | jq -Rs '.' 2>/dev/null || printf '"%s"' "$REASON")
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":%s}}\n' "$RSN"
  exit 2
elif [ "$PCT" -ge 80 ]; then
  MSG="[TOOL LIMIT] $NEW/$CAP tool calls used (${PCT}%). Approaching session cap."
  echo "[Supercharger] tool-call-limiter: $MSG" >&2
  CTX=$(printf '%s' "$MSG" | jq -Rs '.' 2>/dev/null || printf '"%s"' "$MSG")
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":%s}}\n' "$CTX"
  exit 0
fi

exit 0
