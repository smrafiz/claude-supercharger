#!/usr/bin/env bash
# Claude Supercharger — Thinking Budget Control
# Event: UserPromptSubmit | Matcher: (none)
# Classifies prompt complexity and nudges Claude's reasoning depth.

set -euo pipefail
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh"

SCOPE_DIR="$HOME/.claude/supercharger/scope"

# Opt-out
[ -f "$SCOPE_DIR/.no-thinking-control" ] && exit 0

_INPUT=$(cat)
SESSION_ID=$(printf '%s\n' "$_INPUT" | python3 -c "
import sys, json
data = json.load(sys.stdin)
print(data.get('session_id', 'default'))
" 2>/dev/null || echo "default")

PROMPT=$(printf '%s\n' "$_INPUT" | python3 -c "
import sys, json
data = json.load(sys.stdin)
print(data.get('prompt', ''))
" 2>/dev/null || echo "")

[ -z "$PROMPT" ] && exit 0

LEVEL=$(THINKING_PROMPT="$PROMPT" THINKING_SCOPE="$SCOPE_DIR" THINKING_SESSION="$SESSION_ID" python3 -c "
import sys, os, time, re

prompt     = os.environ.get('THINKING_PROMPT', '')
scope_dir  = os.environ.get('THINKING_SCOPE', '')
session_id = os.environ.get('THINKING_SESSION', 'default')

low_verbs  = {'read','show','list','run','yes','no','ok','okay','sure','continue','go','next'}
high_verbs = {'design','architect','plan','debug','investigate','refactor','analyze','migrate','redesign'}

# Agent classification
agent_file = os.path.join(scope_dir, '.agent-classified-' + session_id)
if os.path.isfile(agent_file):
    age = time.time() - os.path.getmtime(agent_file)
    if age < 2:
        try:
            content = open(agent_file).read().strip().lower()
        except Exception:
            content = ''
        high_agents = {'debugger', 'architect', 'planner'}
        low_agents  = {'code-helper', 'general', 'writer'}
        words = prompt.split()
        if any(a in content for a in high_agents):
            print('high')
            sys.exit(0)
        if any(a in content for a in low_agents) and len(words) < 10:
            print('low')
            sys.exit(0)

# Keyword + token count classification
words = prompt.split()
token_count = len(words) * 1.3
prompt_words = set(re.findall(r'\b\w+\b', prompt.lower()))

has_low_verb  = bool(prompt_words & low_verbs)
has_high_verb = bool(prompt_words & high_verbs)
has_question  = '?' in prompt

if has_high_verb or token_count > 200:
    print('high')
elif token_count < 50 and (has_low_verb or (not has_question and len(words) <= 3)):
    print('low')
else:
    print('medium')
" 2>/dev/null || echo "medium")

MSG=""
case "$LEVEL" in
  low)  MSG="[THINK] Trivial task. Respond directly, minimal reasoning." ;;
  high) MSG="[THINK] Complex task. Reason thoroughly before acting." ;;
  *)    exit 0 ;;
esac

echo "[Supercharger] thinking-budget: level=$LEVEL" >&2

CONTEXT_JSON=$(printf '%s' "$MSG" | python3 -c "import sys, json; print(json.dumps(sys.stdin.read()))")
printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":%s}}\n' "$CONTEXT_JSON"

exit 0
