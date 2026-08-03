#!/usr/bin/env bash
# Claude Supercharger — Session Memory Injector
# Event: SessionStart | Matcher: *
# Injects .claude/supercharger-memory.md into context if present.
# Written by session-memory-write.sh on Stop.

set -euo pipefail
HOOKS_DIR="${BASH_SOURCE[0]%/*}"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh"

[ "${SUPERCHARGER_NO_MEMORY:-0}" = "1" ] && exit 0

# v2.26.35: fork-free stdin read. `$(cat)` forks /bin/cat in EVERY hook —
# ~1.8ms each, and 18 blocking hooks fire per Bash tool call. The trailing
# strip reproduces $(cat)'s newline handling so this is byte-identical.
IFS= read -r -d '' _INPUT || true; _INPUT="${_INPUT%"${_INPUT##*[!$'\n']}"}"
PROJECT_DIR=$(printf '%s\n' "$_INPUT" | jq -r '.cwd // .workspace.current_dir // empty' 2>/dev/null || true); [ -z "$PROJECT_DIR" ] && PROJECT_DIR="$PWD"
init_hook_suppress "$PROJECT_DIR"

# --- memory-prune nudge (v2.19.0) ---------------------------------------------
# At most once per week (deduped by a flag's mtime — the weekly gate is checked
# FIRST so the common path is a single stat, no scan), remind (stderr only, zero
# context tokens) if any file-memory entries are marked status: resolved/superseded
# and are still loading their index line every session. Never prunes — just points
# at /memory-prune. Self-contained; cannot affect the memory injection below.
_MP_FLAG="$SUPERCHARGER_STATE/scope/.mem-prune-nudge"
_mp_due=1
if [ -f "$_MP_FLAG" ]; then
  _mp_mt=$(stat -c '%Y' "$_MP_FLAG" 2>/dev/null || stat -f '%m' "$_MP_FLAG" 2>/dev/null || echo 0)
  case "$_mp_mt" in ''|*[!0-9]*) _mp_mt=0 ;; esac
  [ $(( $(date +%s) - _mp_mt )) -lt 604800 ] && _mp_due=0
fi
if [ "$_mp_due" = 1 ]; then
  _mp_enc="-$(printf '%s' "$PROJECT_DIR" | sed 's|/|-|g; s|^-||')"
  _mp_dir="$HOME/.claude/projects/$_mp_enc/memory"
  if [ -d "$_mp_dir" ]; then
    _mp_n=$(grep -lE '^[[:space:]]*status:[[:space:]]*(resolved|superseded)' "$_mp_dir"/*.md 2>/dev/null | grep -vc 'MEMORY.md' || echo 0)
    case "$_mp_n" in ''|*[!0-9]*) _mp_n=0 ;; esac
    if [ "$_mp_n" -gt 0 ]; then
      _mp_word="entries"; [ "$_mp_n" = 1 ] && _mp_word="entry"
      echo "[MEM] $_mp_n resolved memory $_mp_word still loading each session — run /memory-prune to archive." >&2
    fi
    touch "$_MP_FLAG" 2>/dev/null || true
  fi
fi
# ------------------------------------------------------------------------------

MEMORY_FILE="${PROJECT_DIR}/.claude/supercharger-memory.md"

# --- Handoff brief (v2.23.0) ---------------------------------------------------
# The rich /handoff narrative (Done/Decisions/What-failed/Resume-with), loaded at
# session start so a shifted session resumes without re-explaining. Freshness-gated
# to 7 days so a stale brief doesn't flood context forever. Injected in EVERY path
# below (including the no-memory-file and stub paths) — it's the top resume signal.
# post-compact-inject.sh mirrors this at the compaction boundary (no gate there —
# always the same session).
# v2.23.12: handoff is session-scoped (.claude/handoff-<sid>.md). Prefer THIS
# session's own brief, else the newest recent one, else the legacy unsuffixed
# file — all 7-day gated. Shared selector so this and post-compact-inject can't drift.
. "$HOOKS_DIR/lib-handoff.sh"
_HO_SID=$(printf '%s\n' "$_INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)
[ -z "$_HO_SID" ] && _HO_SID="${CLAUDE_CODE_SESSION_ID:-}"
HANDOFF_FILE=$(select_handoff_file "$PROJECT_DIR" "$_HO_SID" 604800)
HANDOFF_BLOCK=""
[ -n "$HANDOFF_FILE" ] && HANDOFF_BLOCK=$(head -c 2500 "$HANDOFF_FILE" 2>/dev/null || echo "")

# Checkpoint recovery fallback
if [ ! -f "$MEMORY_FILE" ]; then
  # Check for crash checkpoint
  CKPT=""
  _NOW_TS=$(date +%s)
  for f in "$SUPERCHARGER_STATE/scope"/.checkpoint-*; do
    [ -f "$f" ] || continue
    # Only use if < 24h old. v2.7.8: bash stat replaces a python3 fork per file
    # (GNU-first, BSD fallback, numeric guard — identical <86400s logic).
    _MT=$(stat -c '%Y' "$f" 2>/dev/null || stat -f '%m' "$f" 2>/dev/null || echo 0)
    case "$_MT" in ''|*[!0-9]*) _MT=0 ;; esac
    if [ "$_MT" -gt 0 ] && [ $((_NOW_TS - _MT)) -lt 86400 ]; then
      CKPT=$(cat "$f" 2>/dev/null)
      break
    else
      rm -f "$f" 2>/dev/null
    fi
  done
  # No mechanical memory doc — still surface a checkpoint and/or the rich handoff.
  if [ -n "$CKPT" ] || [ -n "$HANDOFF_BLOCK" ]; then
    MSG=""
    [ -n "$CKPT" ] && MSG="[RECOVERY] Restored from mid-session checkpoint: $CKPT"
    if [ -n "$HANDOFF_BLOCK" ]; then
      [ -n "$MSG" ] && MSG="$MSG
"
      MSG="${MSG}[HANDOFF] Resume brief from last session:
$HANDOFF_BLOCK"
    fi
    CONTEXT_JSON=$(printf '%s' "$MSG" | jq -Rs '.' 2>/dev/null || printf '"%s"' "$(printf '%s' "$MSG" | tr -d '"\\' | tr '\n' ' ')")
    # v2.7.31: inject into Claude's context (SessionStart supports
    # hookSpecificOutput.additionalContext). systemMessage only reached the USER,
    # so the project memory / checkpoint recovery never entered Claude's context.
    printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":%s}}\n' "$CONTEXT_JSON"
    echo "[Supercharger] session-memory: injected resume brief" >&2
  fi
  exit 0
fi

# Cap at 3000 chars to avoid flooding context
CONTENT=$(head -c 3000 "$MEMORY_FILE" 2>/dev/null || echo "")
[ -z "$CONTENT" ] && exit 0

# Lazy injection: if branch changed or no open work, emit stub only
CURRENT_BRANCH=$(git -C "$PROJECT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
MEM_BRANCH=$(printf '%s' "$CONTENT" | grep -o 'branch:[^ ]*' | cut -d: -f2- || echo "")
MEM_OPEN=$(printf '%s' "$CONTENT" | grep -o 'open:[^ ]*' | cut -d: -f2- || echo "")

if [ -n "$CURRENT_BRANCH" ] && [ -n "$MEM_BRANCH" ] && [ "$CURRENT_BRANCH" != "$MEM_BRANCH" ]; then
  # Switched branches — stub only, avoid injecting stale open-file list
  MSG="[MEM] prev:branch=${MEM_BRANCH} (ask if context needed)"
elif [ "$MEM_OPEN" = "none" ] || [ -z "$MEM_OPEN" ]; then
  # No open work in memory — minimal stub
  MSG="[MEM] prev:branch=${MEM_BRANCH:-?} no open work"
else
  # Active open work on same branch — inject full memory
  # Enrich with live data (v2 enhanced resume)
  ENRICHMENT=""
  # Git diff summary
  DIFF_STAT=$(git -C "$PROJECT_DIR" diff --stat HEAD 2>/dev/null | tail -1 | grep -o '[0-9]* file.*' || echo "")
  [ -n "$DIFF_STAT" ] && ENRICHMENT="${ENRICHMENT} diff:${DIFF_STAT}"
  # Last session cost
  COST_FILE="$SUPERCHARGER_STATE/scope/.session-cost"
  if [ -f "$COST_FILE" ]; then
    # v2.7.8: bash stat + jq replace a python3 fork — identical <86400s mtime
    # guard and total_usd read.
    _CT=$(stat -c '%Y' "$COST_FILE" 2>/dev/null || stat -f '%m' "$COST_FILE" 2>/dev/null || echo 0)
    case "$_CT" in ''|*[!0-9]*) _CT=0 ;; esac
    LAST_COST=""
    if [ "$_CT" -gt 0 ] && [ $(( $(date +%s) - _CT )) -lt 86400 ]; then
      LAST_COST=$(jq -r '.total_usd // empty' "$COST_FILE" 2>/dev/null || echo "")
    fi
    [ -n "$LAST_COST" ] && ENRICHMENT="${ENRICHMENT} last_cost:\$${LAST_COST}"
  fi
  # Recent failures
  PROJECT_ROOT=$(git -C "$PROJECT_DIR" rev-parse --show-toplevel 2>/dev/null || echo "$PROJECT_DIR")
  PROJ_HASH_ENR=$(printf '%s' "$PROJECT_ROOT" | md5sum 2>/dev/null | cut -d' ' -f1 || printf '%s' "$PROJECT_ROOT" | md5 -q 2>/dev/null || echo "global")
  PROJ_HASH_ENR="${PROJ_HASH_ENR:0:8}"
  FAILURE_LOG="$SUPERCHARGER_STATE/scope/.failure-log-${PROJ_HASH_ENR}"
  if [ -f "$FAILURE_LOG" ]; then
    FAILURES=$(tail -10 "$FAILURE_LOG" 2>/dev/null | sort -u | tail -3 | tr '\n' ',' | sed 's/,$//')
    [ -n "$FAILURES" ] && ENRICHMENT="${ENRICHMENT} failures:${FAILURES}"
  fi
  # v2.9.12: hot files — the files the last session most actively edited, ranked
  # by recency-decayed edit frequency. Reuses audit-trail's Write/Edit entries
  # (keys: tool, file, timestamp) — no new tracking. Gives resume a focus list
  # (what we were working ON), not the flat modified-files diff. Idea adapted
  # from thebrain's "file heat" — as a memory signal, not a guard.
  HOT=$(PROJECT_ROOT="$PROJECT_ROOT" AUDIT_DIR="$SUPERCHARGER_STATE/audit" python3 <<'PYEOF' 2>/dev/null || true
import os, json, glob, datetime
root = os.environ.get('PROJECT_ROOT', '')
adir = os.environ.get('AUDIT_DIR', '')
if not root or not os.path.isdir(adir):
    raise SystemExit
now = datetime.datetime.now(datetime.timezone.utc)
scores = {}
for fp in sorted(glob.glob(os.path.join(adir, '*.jsonl')))[-2:]:  # today + yesterday
    try:
        fh = open(fp)
    except Exception:
        continue
    for ln in fh:
        try:
            d = json.loads(ln)
        except Exception:
            continue
        if d.get('tool') not in ('Write', 'Edit'):
            continue
        path = d.get('file') or ''
        if not path or not path.startswith(root):
            continue
        try:
            t = datetime.datetime.fromisoformat((d.get('timestamp') or '').replace('Z', '+00:00'))
            age_h = (now - t).total_seconds() / 3600
        except Exception:
            age_h = 24
        if age_h > 48:
            continue
        scores[path] = scores.get(path, 0) + max(0.15, 1 - age_h / 48)  # linear decay
if scores:
    top = sorted(scores.items(), key=lambda kv: kv[1], reverse=True)[:4]
    print(','.join(os.path.basename(p) for p, _ in top))
PYEOF
)
  [ -n "$HOT" ] && ENRICHMENT="${ENRICHMENT} hot:${HOT}"
  MSG="[MEM] ${CONTENT}${ENRICHMENT}"
fi

# Append recent session observations (last 3 entries) if present
OBS_FILE="${PROJECT_DIR}/.claude/session-observations.md"
if [ -f "$OBS_FILE" ]; then
  OBS=$(python3 -c "
import sys
lines = open(sys.argv[1]).read()
# Extract up to 3 most recent entries (each starts with '## ')
import re
entries = re.split(r'(?=^## )', lines, flags=re.MULTILINE)
entries = [e.strip() for e in entries if e.strip() and e.startswith('## ')]
recent = entries[:3]
if recent:
    # Compress: keep first 2 lines per entry
    compressed = []
    for e in recent:
        head = '\n'.join(e.splitlines()[:4])
        compressed.append(head)
    print(' | '.join(compressed))
" "$OBS_FILE" 2>/dev/null || echo "")
  [ -n "$OBS" ] && MSG="${MSG} obs:${OBS}"
fi

# v2.23.0: append the rich handoff brief (fresh, gated above) after the mechanical
# memory line — even on the branch-changed / no-open-work stub paths, since it's
# the highest-value resume signal.
if [ -n "$HANDOFF_BLOCK" ]; then
  MSG="${MSG}
[HANDOFF] Resume brief from last session:
$HANDOFF_BLOCK"
fi

CONTEXT_JSON=$(printf '%s' "$MSG" | jq -Rs '.' 2>/dev/null || printf '"%s"' "$(printf '%s' "$MSG" | tr -d '"\\' | tr '\n' ' ')")
# v2.7.31: the main memory injection must reach CLAUDE — SessionStart supports
# hookSpecificOutput.additionalContext; systemMessage only reached the USER, so
# the project memory was never actually entering Claude's context.
printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":%s}}\n' "$CONTEXT_JSON"

echo "[Supercharger] session-memory: injected $MEMORY_FILE" >&2
exit 0
