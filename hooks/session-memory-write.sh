#!/usr/bin/env bash
# Claude Supercharger — Session Memory Writer
# Event: Stop | Matcher: *
# Writes a compressed session summary to .claude/supercharger-memory.md
# in the project root. Injected at next SessionStart by session-memory-inject.sh.
# Opt-out: set SUPERCHARGER_NO_MEMORY=1 in your environment.

set -euo pipefail

[ "${SUPERCHARGER_NO_MEMORY:-0}" = "1" ] && exit 0

# Must be in a project with .claude/ dir
[ ! -d ".claude" ] && exit 0

_INPUT=$(cat 2>/dev/null || echo "")

MEMORY_FILE=".claude/supercharger-memory.md"
AUDIT_DIR="$HOME/.claude/supercharger/audit"
TODAY=$(date -u +"%Y-%m-%d")
AUDIT_FILE="$AUDIT_DIR/$TODAY.jsonl"
SCOPE_DIR="$HOME/.claude/supercharger/scope"

# --- Uncommitted changed files only (open work) ---
# v2.6.19: one `git status --porcelain` replaces 3 separate git diff/ls-files
# calls. status emits a line per file with a 2-char status prefix; strip the
# prefix and dedupe. Cuts ~30ms off the hook (3 git cold starts → 1).
OPEN_FILES=$(git status --porcelain 2>/dev/null | sed 's/^...//' | sort -u | grep -v '^$' | head -15 | sed 's/^/- /' || echo "")

# --- Recent commits (completed decisions) ---
RECENT_COMMITS=$(git log --oneline -3 2>/dev/null || echo "")

# --- Branch ---
BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")

# --- Recent corrections (last 5, project-scoped) ---
CORRECTIONS=""
PROJECT_DIR=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
PROJ_HASH=$(printf '%s' "$PROJECT_DIR" | md5sum 2>/dev/null | cut -d' ' -f1 || printf '%s' "$PROJECT_DIR" | md5 -q 2>/dev/null || echo "global")
PROJ_HASH="${PROJ_HASH:0:8}"
CORRECTIONS_FILE="$SCOPE_DIR/.user-corrections-${PROJ_HASH}"
# Fall back to global file if project-scoped one doesn't exist yet
if [ -f "$CORRECTIONS_FILE" ]; then
  CORRECTIONS=$(tail -5 "$CORRECTIONS_FILE" 2>/dev/null || echo "")
elif [ -f "$SCOPE_DIR/.user-corrections" ]; then
  CORRECTIONS=$(tail -5 "$SCOPE_DIR/.user-corrections" 2>/dev/null || echo "")
fi

# --- Decisions extracted from this turn's assistant messages ---
DECISIONS_LINE="none"
TRANSCRIPT=$(printf '%s\n' "$_INPUT" | jq -r '.transcript_path // empty' 2>/dev/null || true)
if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
  # v2.6.21: tail the transcript inside python (the previous v2.6.19 attempt
  # piped `tail` into python with a heredoc, but the `<<'PYEOF'` heredoc
  # silently overrides the piped stdin — python read its own source code,
  # never the transcript. Shellcheck SC2259 caught this. Move the tail into
  # python itself: read the file, keep the last 200 lines. Same O(constant)
  # cost characteristic, but no stdin conflict.
  DECISIONS_LINE=$(TRANSCRIPT="$TRANSCRIPT" python3 <<'PYEOF'
import os, json, re
from collections import deque
path = os.environ.get('TRANSCRIPT', '')
texts = []
try:
    with open(path) as f:
        lines = deque(f, maxlen=200)
    for line in lines:
        try:
            obj = json.loads(line)
        except Exception:
            continue
        if obj.get('type') != 'assistant':
            continue
        content = (obj.get('message') or {}).get('content') or []
        if isinstance(content, list):
            for part in content:
                if isinstance(part, dict) and part.get('type') == 'text':
                    t = part.get('text', '')
                    if t:
                        texts.append(t)
except Exception:
    raise SystemExit(0)
if not texts:
    raise SystemExit(0)

# Scan the last 5 assistant messages for decision phrases
recent = ' '.join(texts[-5:])
patterns = [
    r"\b(?:I'?ll|I will|I'?m going to|going with)\s+([^.\n]{10,140}?)\s+(?:because|since|so that|to)\s+([^.\n]{5,120})",
    r"\bdecided to\s+([^.\n]{10,140}?)(?:\s+(?:because|since)\s+([^.\n]{5,120}))?",
    r"\bskipped?\s+([^.\n]{5,120}?)\s+(?:because|since|to)\s+([^.\n]{5,120})",
    r"\bchose\s+([^.\n]{5,140}?)\s+(?:over|for|because|since)\s+([^.\n]{5,120})",
]
seen = set()
out = []
for pat in patterns:
    for m in re.finditer(pat, recent, re.IGNORECASE):
        action = m.group(1).strip().rstrip(',;:')
        reason = (m.group(2) or '').strip().rstrip('.,;:')
        if reason:
            line = f"{action[:80]} ({reason[:60]})"
        else:
            line = action[:120]
        key = action.lower()[:40]
        if key in seen:
            continue
        seen.add(key)
        out.append(line)
        if len(out) >= 5:
            break
    if len(out) >= 5:
        break
if out:
    print('|'.join(out))
PYEOF
)
  [ -z "$DECISIONS_LINE" ] && DECISIONS_LINE="none"
fi

# --- Build dense key=value format (~40% fewer tokens than Markdown) ---
TIMESTAMP=$(date -u '+%Y-%m-%dT%H:%MZ')
OPEN_CSV=$(printf '%s\n' "$OPEN_FILES" | sed 's/^- //' | grep -v '^$' | tr '\n' ',' | sed 's/,$//' || true)
COMMITS_CSV=$(printf '%s\n' "$RECENT_COMMITS" | grep -v '^$' | sed 's/ /:/' | tr '\n' '|' | sed 's/|$//' || true)
CORR_LINE=$(printf '%s\n' "$CORRECTIONS" | grep -v '^$' | tr '\n' '|' | sed 's/|$//' || true)

CONTENT="mem:${TIMESTAMP} branch:${BRANCH} open:${OPEN_CSV:-none} commits:${COMMITS_CSV:-none} corrections:${CORR_LINE:-none} decisions:${DECISIONS_LINE}"

# --- #11 Differential write: skip if open-work, commits, AND decisions unchanged ---
if [ -f "$MEMORY_FILE" ]; then
  PREV=$(cat "$MEMORY_FILE" 2>/dev/null)
  PREV_OPEN=$(printf '%s' "$PREV" | grep -o 'open:[^ ]*' | cut -d: -f2-)
  PREV_COMMITS=$(printf '%s' "$PREV" | grep -o 'commits:[^ ]*' | cut -d: -f2-)
  PREV_DECISIONS=$(printf '%s' "$PREV" | sed -n 's/.*decisions:\(.*\)/\1/p')
  if [ "$PREV_OPEN" = "${OPEN_CSV:-none}" ] && [ "$PREV_COMMITS" = "${COMMITS_CSV:-none}" ] && [ "$PREV_DECISIONS" = "$DECISIONS_LINE" ]; then
    echo "[Supercharger] session-memory: no changes, skipping write" >&2
    exit 0
  fi
fi

# Truncate to 2000 chars
printf '%.1200s\n' "$CONTENT" > "$MEMORY_FILE"

echo "[Supercharger] session-memory: wrote $MEMORY_FILE" >&2

# Clean up checkpoint files (successful memory write = no longer needed)
rm -f "$HOME/.claude/supercharger/scope"/.checkpoint-* 2>/dev/null || true

exit 0
