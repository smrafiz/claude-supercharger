#!/usr/bin/env bash
# Claude Supercharger — Lesson Recorder (Reflexion Memory)
# Event: Stop | Matcher: *
# Scans assistant's last transcript message for diagnostic markers
# (the issue was, root cause, fixed by, ...) and appends a structured
# lesson record to <repo>/.claude/supercharger/lessons.jsonl.
# Disable: SUPERCHARGER_LESSONS=0

set -euo pipefail
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh"

[ "${SUPERCHARGER_LESSONS:-1}" = "0" ] && exit 0

_INPUT=$(cat)
PROJECT_DIR=$(printf '%s\n' "$_INPUT" | jq -r '.cwd // empty' 2>/dev/null); [ -z "$PROJECT_DIR" ] && PROJECT_DIR="$PWD"
init_hook_suppress "$PROJECT_DIR"
check_hook_disabled "lesson-record" && exit 0
hook_profile_skip "lesson-record" && exit 0

TRANSCRIPT=$(printf '%s\n' "$_INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
[ -z "$TRANSCRIPT" ] || [ ! -f "$TRANSCRIPT" ] && exit 0

LAST_USER=$(jq -rs '
  [.[] | select(.type == "user")] | last |
  if .message.content | type == "array"
  then [.message.content[] | select(.type == "text") | .text] | join(" ")
  else .message.content // "" end
' "$TRANSCRIPT" 2>/dev/null || echo "")

LAST_ASSIST=$(jq -rs '
  [.[] | select(.type == "assistant" and .message.content)] | last |
  [.message.content[] | select(.type == "text") | .text] | join(" ")
' "$TRANSCRIPT" 2>/dev/null || echo "")

[ -z "$LAST_ASSIST" ] && exit 0

LESSONS_DIR="$PROJECT_DIR/.claude/supercharger"
LESSONS_FILE="$LESSONS_DIR/lessons.jsonl"

RECORD=$(LAST_USER="$LAST_USER" LAST_ASSIST="$LAST_ASSIST" python3 <<'PYEOF'
import os, re, json, datetime

assist = os.environ.get('LAST_ASSIST', '')
user = os.environ.get('LAST_USER', '')

markers = [
    r'the issue was',
    r'root cause',
    r'fixed by',
    r'the problem was',
    r'turns out',
    r'it failed because',
]
pattern = re.compile('|'.join(markers), re.IGNORECASE)
m = pattern.search(assist)
if not m:
    raise SystemExit(0)

idx = m.start()
before = assist[:idx].strip()
after = assist[idx:].strip()

sig = (user[:100] if user else before.split('\n')[-1][:100]).strip()
fix = after[:200].strip()
first_sent = re.split(r'(?<=[.!?])\s', after, maxsplit=1)[0]
lesson = first_sent[:160].strip()

files = re.findall(r'[\w./\-]+\.[a-zA-Z0-9]{1,6}\b', assist)
files = list(dict.fromkeys(files))[:5]

tokens = set()
for txt in (sig, fix):
    for w in re.findall(r'[a-zA-Z0-9_]+', txt.lower()):
        if len(w) >= 3:
            tokens.add(w)
recall = ' '.join(sorted(tokens))

rec = {
    'sig': sig,
    'fix': fix,
    'files': files,
    'lesson': lesson,
    'recall': recall,
    'ts': datetime.datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ'),
}
print(json.dumps(rec))
PYEOF
)

[ -z "$RECORD" ] && exit 0

mkdir -p "$LESSONS_DIR"

if [ -f "$LESSONS_FILE" ]; then
  COUNT=$(wc -l < "$LESSONS_FILE" | tr -d ' ')
  if [ "$COUNT" -ge 1000 ]; then
    tail -n 999 "$LESSONS_FILE" > "$LESSONS_FILE.$$.tmp"
    mv "$LESSONS_FILE.$$.tmp" "$LESSONS_FILE"
  fi
fi

printf '%s\n' "$RECORD" >> "$LESSONS_FILE"
exit 0
