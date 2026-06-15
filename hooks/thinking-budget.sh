#!/usr/bin/env bash
# Claude Supercharger — Thinking Budget Control
# Event: UserPromptSubmit | Matcher: (none)
# Classifies prompt complexity and nudges Claude's reasoning depth.

set -euo pipefail
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh"
hook_profile_skip "thinking-budget" && exit 0

SCOPE_DIR="$HOME/.claude/supercharger/scope"

# Opt-out
[ -f "$SCOPE_DIR/.no-thinking-control" ] && exit 0

_INPUT=$(cat)

# v2.6.15: one python3 fork does parse + classify + JSON-wrap (was 2 jq forks,
# up to 2 python3 forks). UserPromptSubmit is a hot-path event; this drops
# the hook from ~70ms to ~30ms (median, cold start).
RESULT=$(THINKING_SCOPE="$SCOPE_DIR" HOOK_INPUT="$_INPUT" python3 <<'PYEOF' 2>/dev/null
import json, os, sys, re, time

raw = os.environ.get('HOOK_INPUT', '')
try:
    data = json.loads(raw)
except Exception:
    sys.exit(0)

prompt = data.get('prompt') or ''
session_id = data.get('session_id') or 'default'
scope_dir = os.environ.get('THINKING_SCOPE', '')

if not prompt:
    sys.exit(0)

# Explicit flag override (SuperClaude-style)
# --no-think exists because Opus 4.8 has extended thinking ON by default — for
# routine tasks the formal reasoning pass burns output tokens with no quality
# gain. This flag tells Claude to skip it.
level = ''
if '--ultrathink' in prompt or '--think-hard' in prompt:
    level = 'ultra'
elif '--no-think' in prompt or '--nothink' in prompt:
    level = 'off'
elif '--think' in prompt:
    level = 'high'

if not level:
    low_verbs  = {'read','show','list','run','yes','no','ok','okay','sure','continue','go','next'}
    high_verbs = {'design','architect','plan','debug','investigate','refactor','analyze','migrate','redesign'}

    # Agent classification (fresh within 2s)
    agent_file = os.path.join(scope_dir, '.agent-classified-' + session_id)
    if scope_dir and os.path.isfile(agent_file):
        try:
            if time.time() - os.path.getmtime(agent_file) < 2:
                content = open(agent_file).read().strip().lower()
                high_agents = {'debugger', 'architect', 'planner'}
                low_agents  = {'code-helper', 'general', 'writer'}
                words = prompt.split()
                if any(a in content for a in high_agents):
                    level = 'high'
                elif any(a in content for a in low_agents) and len(words) < 10:
                    level = 'low'
        except Exception:
            pass

    if not level:
        words = prompt.split()
        token_count = len(words) * 1.3
        prompt_words = set(re.findall(r'\b\w+\b', prompt.lower()))
        has_low_verb  = bool(prompt_words & low_verbs)
        has_high_verb = bool(prompt_words & high_verbs)
        has_question  = '?' in prompt
        if has_high_verb or token_count > 200:
            level = 'high'
        elif token_count < 50 and (has_low_verb or (not has_question and len(words) <= 3)):
            level = 'low'
        else:
            level = 'medium'

messages = {
    'off':   '[THINK] Skip extended thinking. Opus 4.8 defaults to on but this prompt does not need a formal reasoning pass — answer directly. Saves output tokens.',
    'low':   '[THINK] Trivial task. Respond directly, minimal reasoning.',
    'high':  '[THINK] Complex task. Reason thoroughly before acting.',
    'ultra': '[THINK] User requested deep reasoning (--ultrathink/--think-hard). Plan exhaustively, verify each step, justify decisions, surface trade-offs. Use full reasoning budget.',
}
msg = messages.get(level)
if not msg:
    sys.exit(0)

print(level)
print(json.dumps({
    'hookSpecificOutput': {
        'hookEventName': 'UserPromptSubmit',
        'additionalContext': msg,
    }
}))
PYEOF
)

[ -z "$RESULT" ] && exit 0

LEVEL=$(printf '%s' "$RESULT" | head -1)
JSON=$(printf '%s' "$RESULT" | sed -n '2p')

echo "[Supercharger] thinking-budget: level=$LEVEL" >&2
printf '%s\n' "$JSON"

exit 0
