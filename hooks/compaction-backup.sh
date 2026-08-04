#!/usr/bin/env bash
# Claude Supercharger — Compaction Backup Hook
# Event: PreCompact | Matcher: (none)
# Saves conversation transcript before context compaction.
# Also ensures summaries directory exists for Claude to write session summaries.

set -euo pipefail

# v2.23.44: honor the global kill-switch — /sc off must silence EVERY hook. Sourcing
# lib-timing exits at source time when the disable flag is set (and adds /perf timing).
# shellcheck source=hooks/lib-timing.sh
. "${BASH_SOURCE[0]%/*}/lib-timing.sh" 2>/dev/null || true

BACKUP_DIR="$HOME/.claude/backups/transcripts"
# Resolve state/code roots for both installer and plugin runtimes (see lib-paths.sh).
. "${BASH_SOURCE[0]%/*}/lib-paths.sh" 2>/dev/null || true
: "${SUPERCHARGER_STATE:=${CLAUDE_PLUGIN_DATA:-$HOME/.claude/supercharger}}"
: "${SUPERCHARGER_HOME:=${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/supercharger}}"

SUMMARIES_DIR="$SUPERCHARGER_STATE/summaries"
mkdir -p "$BACKUP_DIR"
mkdir -p "$SUMMARIES_DIR"
chmod 700 "$BACKUP_DIR"
chmod 700 "$SUMMARIES_DIR"

TIMESTAMP=$(date +%Y-%m-%d-%H%M%S)
BACKUP_FILE="$BACKUP_DIR/$TIMESTAMP.md"

# v2.26.35: fork-free stdin read. `$(cat)` forks /bin/cat in EVERY hook —
# ~1.8ms each, and 18 blocking hooks fire per Bash tool call. The trailing
# strip reproduces $(cat)'s newline handling so this is byte-identical.
IFS= read -r -d '' _INPUT || true; _INPUT="${_INPUT%"${_INPUT##*[!$'\n']}"}"
printf '%s\n' "$_INPUT" > "$BACKUP_FILE"
chmod 600 "$BACKUP_FILE"

echo "[Supercharger] compaction-backup: transcript backed up to $BACKUP_FILE" >&2
echo "[Supercharger] compaction-backup: session summary directory ready at $SUMMARIES_DIR" >&2

# Rotate: remove backups older than 30 days (at most once per day)
ROTATION_CHECK="$BACKUP_DIR/.last-rotation"
NOW=$(date +%s)
LAST_ROTATION=$(cat "$ROTATION_CHECK" 2>/dev/null || echo "0")
[ -z "$LAST_ROTATION" ] && LAST_ROTATION=0
if (( NOW - LAST_ROTATION > 86400 )); then
  find "$BACKUP_DIR" -name "*.md" -mtime +30 -delete 2>/dev/null || true
  echo "$NOW" > "$ROTATION_CHECK"
fi

# --- Handoff discoverability nudge (v2.23.1) ----------------------------------
# Users know /compact; most don't know /handoff. Compaction is the exact moment a
# richer resume brief pays off, so emit a ONE-TIME (per project) stderr hint —
# zero context tokens. Skipped when memory is disabled, when a fresh handoff
# already exists (they know the feature), or via SUPERCHARGER_HANDOFF_NUDGE=0.
if [ "${SUPERCHARGER_NO_MEMORY:-0}" != "1" ] && [ "${SUPERCHARGER_HANDOFF_NUDGE:-1}" != "0" ]; then
  _HN_SCOPE="$SUPERCHARGER_STATE/scope"
  _HN_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")
  . "${BASH_SOURCE[0]%/*}/lib-hash.sh" 2>/dev/null || true
  _HN_HASH=$(printf '%s' "$_HN_ROOT" | sc_md5 2>/dev/null || true); [ -z "$_HN_HASH" ] && _HN_HASH="global"
  _HN_FLAG="$_HN_SCOPE/.handoff-nudge-${_HN_HASH:0:8}"
  # v2.23.12: handoff is session-scoped; skip the nudge if any recent brief exists
  # (own-SID preferred, else newest, else legacy). Shared selector = no drift.
  . "${BASH_SOURCE[0]%/*}/lib-handoff.sh"
  _HN_SID=$(printf '%s\n' "$_INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)
  [ -z "$_HN_SID" ] && _HN_SID="${CLAUDE_CODE_SESSION_ID:-}"
  _HN_FRESH=0
  [ -n "$(select_handoff_file "$_HN_ROOT" "$_HN_SID" 604800)" ] && _HN_FRESH=1
  if [ "$_HN_FRESH" = 0 ] && [ ! -f "$_HN_FLAG" ]; then
    mkdir -p "$_HN_SCOPE" 2>/dev/null || true
    touch "$_HN_FLAG" 2>/dev/null || true
    echo "[Supercharger] Tip: run /handoff before you stop — it writes a fuller resume brief that auto-loads after this compaction and in your next session. (silence: SUPERCHARGER_HANDOFF_NUDGE=0)" >&2
  fi
fi

# v2.6.34: parallelize the two inline child hooks (session-memory-write and
# lesson-record). Both read transcript / scope files independently; running
# them concurrently overlaps the IO + python cold-starts. wait blocks until
# both finish — still race-free vs the post-fix in v2.6.5. Cuts ~70ms off
# the sync PreCompact path.
HOOKS_DIR="${BASH_SOURCE[0]%/*}"
if [ -f "$HOOKS_DIR/session-memory-write.sh" ]; then
  printf '%s\n' "$_INPUT" | bash "$HOOKS_DIR/session-memory-write.sh" 2>/dev/null &
fi
if [ -f "$HOOKS_DIR/lesson-record.sh" ]; then
  printf '%s\n' "$_INPUT" | bash "$HOOKS_DIR/lesson-record.sh" 2>/dev/null &
fi
wait

# v2.6.34: one python3 fork does git diff + cost read + JSON wrap.
# Was 3 forks (git diff + tr + sed pipeline, python3 cost read, jq -Rs).
# git diff stays a subprocess INSIDE python — same total cost, one fewer
# python cold-start.
SCOPE_DIR="$SUPERCHARGER_STATE/scope"
GUIDANCE=$(SCOPE_DIR="$SCOPE_DIR" python3 <<'PYEOF' 2>/dev/null
import json, os, subprocess

scope_dir = os.environ['SCOPE_DIR']
parts = []

# Modified files
try:
    out = subprocess.check_output(['git', 'diff', '--name-only', 'HEAD'],
                                  stderr=subprocess.DEVNULL, timeout=2).decode()
    files = [f for f in out.splitlines() if f][:10]
    if files:
        parts.append('PRESERVE modified files: ' + ','.join(files) + '.')
except Exception:
    pass

# Economy tier
try:
    with open(os.path.join(scope_dir, '.economy-tier')) as f:
        tier = f.read().strip()
    if tier:
        parts.append('PRESERVE economy: ' + tier + '.')
except Exception:
    pass

# v2.7.61: .session-cost total_usd is the machine-GLOBAL accumulator (it is not
# reset per session), so labelling it "Session cost" was misleading (e.g. showed
# $53609.92 lifetime as if it were one session). Label it accurately and round to
# cents instead of dumping the raw 8-decimal float.
try:
    with open(os.path.join(scope_dir, '.session-cost')) as f:
        cost = json.load(f).get('total_usd', '')
    if cost != '':
        try:
            cost = f'{float(cost):.2f}'
        except Exception:
            pass
        parts.append(f'Total cost so far (all sessions): ${cost}.')
except Exception:
    pass

if not parts:
    exit(0)
guidance = '[COMPACT] ' + ' '.join(parts) + ' DISCARD: full file contents, verbose tool output, completed task details.'
print(json.dumps({'systemMessage': guidance, 'suppressOutput': True}))
PYEOF
)

[ -n "$GUIDANCE" ] && printf '%s\n' "$GUIDANCE"
exit 0
