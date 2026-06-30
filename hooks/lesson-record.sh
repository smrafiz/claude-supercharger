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

# v2.7.14: CC re-fires Stop repeatedly (stop_hook_active re-entry — e.g. when
# stop-keep-going/stop-verify return a block). Each re-fire sees the SAME last
# assistant message and would append an IDENTICAL lesson, so lessons.jsonl
# accumulated N duplicates per lesson (and lesson-recall surfaced them N times).
# Skip re-entries — only record on the first/terminal stop. Same guard idiom as
# notify-stop.sh.
STOP_ACTIVE=$(printf '%s\n' "$_INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null || echo false)
[ "$STOP_ACTIVE" = "true" ] && exit 0

PROJECT_DIR=$(printf '%s\n' "$_INPUT" | jq -r '.cwd // .workspace.current_dir // empty' 2>/dev/null || true); [ -z "$PROJECT_DIR" ] && PROJECT_DIR="$PWD"
init_hook_suppress "$PROJECT_DIR"
check_hook_disabled "lesson-record" && exit 0
hook_profile_skip "lesson-record" && exit 0

TRANSCRIPT=$(printf '%s\n' "$_INPUT" | jq -r '.transcript_path // empty' 2>/dev/null || true)
[ -z "$TRANSCRIPT" ] || [ ! -f "$TRANSCRIPT" ] && exit 0

# Single jq fork extracts both LAST_USER and LAST_ASSIST in one transcript
# pass — replaces two separate jq -rs full-file reads. Output is delimited by
# US (\x1f) which never appears in transcript text. Saves one full-file parse
# (transcripts grow large in long sessions; the second parse was the big cost).
PAIR=$(jq -rs '
  ([.[] | select(.type == "user")] | last) as $u |
  ([.[] | select(.type == "assistant" and .message.content)] | last) as $a |
  (
    if $u.message.content | type == "array"
    then [$u.message.content[] | select(.type == "text") | .text] | join(" ")
    else $u.message.content // "" end
  )
  + "__SC_SEP__"
  + ([$a.message.content[] | select(.type == "text") | .text] | join(" "))
' "$TRANSCRIPT" 2>/dev/null || echo "__SC_SEP__")
LAST_USER="${PAIR%%__SC_SEP__*}"
LAST_ASSIST="${PAIR#*__SC_SEP__}"

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

# v2.7.18: quality gate. The old code took marker-to-EOF and the first sentence,
# so prose like "...the offset drifted (root cause)." recorded the fragment
# "root cause)." — and it fired on ANY message merely mentioning a marker (a
# dashboard, a commit summary), polluting lessons.jsonl with junk that
# lesson-recall then re-injected. Now: (1) reject parenthetical asides like
# "(root cause)"; (2) extract the FULL sentence containing the marker, not just
# the tail; (3) require a substantive sentence (length + word count) so
# fragments are dropped.
if assist[max(0, idx - 1):idx] == '(':
    raise SystemExit(0)

# Sentence start: just after the previous sentence terminator.
sent_start = 0
for b in re.finditer(r'[.!?]\s', assist[:idx]):
    sent_start = b.end()
# Sentence end: the next terminator at/after the marker.
end_m = re.search(r'[.!?](\s|$)', assist[idx:])
sent_end = idx + end_m.end() if end_m else len(assist)
sentence = assist[sent_start:sent_end]
# Strip leading markdown/list/punctuation noise and collapse whitespace.
sentence = re.sub(r'^[\s\-*#>`)\].,:;]+', '', sentence)
sentence = re.sub(r'\s+', ' ', sentence).strip()

words = re.findall(r'[a-zA-Z0-9]+', sentence)
if len(sentence) < 30 or len(words) < 6:
    raise SystemExit(0)

# Reject the assistant NARRATING about debugging ("I can't pin the root cause
# down…", "Let me check the root cause") vs. STATING a finding ("Root cause:
# the cache TTL was 5min", "Fixed by adding a guard"). Real code lessons are
# declarative and don't use first-person/conversational language. The standalone
# capital "I" must be case-SENSITIVE (lowercasing would match in/is/it).
if (re.search(r"(^|\s)(I|I['’](m|ll|d|ve))(\s|['’]|$)", sentence)
        or re.search(r"\blet me\b", sentence, re.IGNORECASE)):
    raise SystemExit(0)

before = assist[:idx].strip()
sig = (user[:100] if user else before.split('\n')[-1][:100]).strip()
fix = sentence[:200].strip()
lesson = sentence[:200].strip()

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
