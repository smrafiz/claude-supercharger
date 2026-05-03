#!/usr/bin/env bash
# Claude Supercharger — Lesson Recaller (Reflexion Memory)
# Event: UserPromptSubmit | Matcher: (none)
# Tokenizes user prompt, computes Jaccard overlap against stored
# lessons.jsonl, injects top 3 matches above threshold 0.5.
# Output is tier-scaled.
# Disable: SUPERCHARGER_LESSONS=0

set -euo pipefail
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh"

[ "${SUPERCHARGER_LESSONS:-1}" = "0" ] && exit 0

_INPUT=$(cat)
PROJECT_DIR=$(printf '%s\n' "$_INPUT" | jq -r '.cwd // empty' 2>/dev/null); [ -z "$PROJECT_DIR" ] && PROJECT_DIR="$PWD"
init_hook_suppress "$PROJECT_DIR"
check_hook_disabled "lesson-recall" && exit 0
hook_profile_skip "lesson-recall" && exit 0

PROMPT=$(printf '%s\n' "$_INPUT" | jq -r '.prompt // empty' 2>/dev/null)
if [ -z "$PROMPT" ]; then
  PROMPT=$(printf '%s\n' "$_INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('prompt',''))" 2>/dev/null || echo "")
fi
[ -z "$PROMPT" ] && exit 0

DIR="$PROJECT_DIR"
LESSONS_FILE=""
while [ "$DIR" != "/" ] && [ -n "$DIR" ]; do
  if [ -f "$DIR/.claude/supercharger/lessons.jsonl" ]; then
    LESSONS_FILE="$DIR/.claude/supercharger/lessons.jsonl"
    break
  fi
  DIR=$(dirname "$DIR")
done
[ -z "$LESSONS_FILE" ] && exit 0

TIER="${SUPERCHARGER_TIER:-standard}"

OUT=$(PROMPT="$PROMPT" LESSONS_FILE="$LESSONS_FILE" TIER="$TIER" python3 <<'PYEOF'
import os, re, json

prompt = os.environ.get('PROMPT', '')
path = os.environ.get('LESSONS_FILE', '')
tier = os.environ.get('TIER', 'standard')

def tokenize(text):
    return {w for w in re.findall(r'[a-zA-Z0-9_]+', text.lower()) if len(w) >= 3}

p_tokens = tokenize(prompt)
if not p_tokens:
    raise SystemExit(0)

scored = []
try:
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                rec = json.loads(line)
            except Exception:
                continue
            r_tokens = tokenize(rec.get('recall', ''))
            if not r_tokens:
                continue
            inter = len(p_tokens & r_tokens)
            union = len(p_tokens | r_tokens)
            score = inter / union if union else 0
            if score >= 0.5:
                scored.append((score, rec))
except FileNotFoundError:
    raise SystemExit(0)

scored.sort(key=lambda x: x[0], reverse=True)
top = [r for _, r in scored[:3]]
if not top:
    raise SystemExit(0)

if tier == 'minimal':
    print('[lessons: ' + str(len(top)) + ' matched]')
elif tier == 'lean':
    for r in top:
        print('- ' + r.get('lesson', ''))
else:
    parts = []
    for r in top:
        block = '- ' + r.get('lesson', '')
        if r.get('fix'):
            block += '\n  fix: ' + r['fix']
        if r.get('files'):
            block += '\n  files: ' + ', '.join(r['files'])
        parts.append(block)
    print('\n'.join(parts))
PYEOF
)

[ -z "$OUT" ] && exit 0

OUT_JSON=$(printf '%s' "$OUT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))")
printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":%s}}\n' "$OUT_JSON"
exit 0
