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
HOOKS_DIR="${BASH_SOURCE[0]%/*}"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh"
# shellcheck source=hooks/lib-project-root.sh
. "$HOOKS_DIR/lib-project-root.sh"
# shellcheck source=hooks/lib-json-fast.sh
. "$HOOKS_DIR/lib-json-fast.sh" 2>/dev/null || true
check_hook_disabled "tool-call-limiter" && exit 0

# v2.26.35: fork-free stdin read. `$(cat)` forks /bin/cat in EVERY hook —
# ~1.8ms each, and 18 blocking hooks fire per Bash tool call. The trailing
# strip reproduces $(cat)'s newline handling so this is byte-identical.
IFS= read -r -d '' -t "${SUPERCHARGER_STDIN_TIMEOUT_S:-5}" _INPUT || [ $? -le 128 ] || _INPUT=""; _INPUT="${_INPUT%"${_INPUT##*[!$'\n']}"}"

# ── Resolve cap ───────────────────────────────────────────────────────────────
CAP=""
if [ -n "${SESSION_MAX_TOOL_CALLS:-}" ]; then
  CAP="$SESSION_MAX_TOOL_CALLS"
else
  # v2.24.0: fork-free `cwd` read (this hook has an empty matcher — it fires on every
  # tool call), with the original jq kept as the fallback for anything ambiguous.
  PROJECT_DIR=""
  if command -v _json_fast_str >/dev/null 2>&1 && _json_fast_str cwd "$_INPUT"; then
    PROJECT_DIR="$_JSON_FAST_VAL"
  else
    PROJECT_DIR=$(printf '%s\n' "$_INPUT" | jq -r '.cwd // .workspace.current_dir // empty' 2>/dev/null || true)
  fi
  [ -z "$PROJECT_DIR" ] && PROJECT_DIR="$PWD"
  # v2.6.36: walk from main worktree root if PROJECT_DIR is a linked worktree
  SEARCH_DIR=$(_resolve_project_root "$PROJECT_DIR")
  for _ in 1 2 3 4 5; do
    if [ -f "$SEARCH_DIR/.supercharger.json" ]; then
      # v2.24.0: only fork python if the key is actually present. Most projects have a
      # .supercharger.json without `maxToolCalls`, and this was paying ~30ms to learn
      # that. Reading the file is a builtin redirect; the substring test is fork-free.
      # Same terminal state as before when absent (empty CAP -> no limit).
      _TCL_CFG_BODY=$(<"$SEARCH_DIR/.supercharger.json")
      case "$_TCL_CFG_BODY" in
        *maxToolCalls*) ;;
        *) break ;;
      esac
      # 2.21.13: pass the path via env, not string-interpolation. A project dir
      # containing a single quote (e.g. o'malley) broke the python string literal
      # → SyntaxError → CAP empty → the limiter silently disabled itself.
      # v2.28.8: pass the CONTENT, not the path. bash has already read the file into
      # _TCL_CFG_BODY two lines above, so handing python a path made it re-open a
      # file we hold in memory — and made the read depend on that path surviving the
      # trip. The recon has this failing on Git Bash for a directory containing an
      # apostrophe while the identical case with an ordinary name passes, i.e.
      # something about the path is not arriving intact. Rather than guess which
      # layer mangles it, the dependency is removed: there is no path to convert,
      # no second open, and one less fork's worth of filesystem work.
      CAP=$(printf '%s' "$_TCL_CFG_BODY" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    v = d.get('maxToolCalls', '')
    print(str(int(v)) if v else '')
except Exception:
    print('')
" 2>/dev/null || echo "")
      break
    fi
    # v2.24.0: parameter expansion instead of a dirname fork (up to 5 per fire).
    PARENT="${SEARCH_DIR%/*}"
    [ -z "$PARENT" ] && PARENT="/"
    [ "$PARENT" = "$SEARCH_DIR" ] && break
    SEARCH_DIR="$PARENT"
  done
fi

[ -z "$CAP" ] && exit 0

# ── Session scoping ───────────────────────────────────────────────────────────
SCOPE_DIR="$SUPERCHARGER_STATE/scope"
mkdir -p "$SCOPE_DIR"

# 2.22.7: prefer the session id from the PAYLOAD (like every sibling hook). CC
# delivers session_id in the hook JSON, not as an env var, so CLAUDE_SESSION_ID
# was almost always empty and SESSION_KEY fell back to the calendar date — making
# the "per-session" cap a per-DAY, machine-GLOBAL counter shared by every
# concurrent session (cross-session DoS + a limit that resets at midnight).
SESSION_KEY=$(printf '%s\n' "$_INPUT" | jq -r '.session_id // empty' 2>/dev/null | tr -cd 'a-zA-Z0-9_-' | head -c 64 || true)
[ -z "$SESSION_KEY" ] && SESSION_KEY="${CLAUDE_SESSION_ID:-$(date +%Y%m%d)}"
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
