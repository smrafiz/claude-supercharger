#!/usr/bin/env bash
# Claude Supercharger — Agent Router
# Event: UserPromptSubmit | Matcher: (none)
# Classifies each user prompt and injects a routing directive into
# Claude's context. Updates .agent-route for agent-gate.sh reference.

set -euo pipefail

SUPERCHARGER_DIR="$HOME/.claude/supercharger"
SCOPE_DIR="$SUPERCHARGER_DIR/scope"
mkdir -p "$SCOPE_DIR"

ROUTE_FILE="$SCOPE_DIR/.agent-route"

PROMPT=$(python3 -c "
import sys, json
try:
    print(json.load(sys.stdin).get('prompt', ''))
except:
    print('')
" 2>/dev/null || echo "")

[ -z "$PROMPT" ] && exit 0

AGENT=""

# Ordered by specificity — most specific first
if printf '%s\n' "$PROMPT" | grep -qiE '(error|exception|stack trace|not working|broken|failing|crash|null pointer|undefined is not|bug at line|segfault|traceback|exit code [0-9])'; then
  AGENT="Sherlock Holmes (Detective)"
elif printf '%s\n' "$PROMPT" | grep -qiE '(review|security issue|code smell|what do you think of|look at this|check my|critique|audit this|LGTM)'; then
  AGENT="Gordon Ramsay (Critic)"
elif printf '%s\n' "$PROMPT" | grep -qiE '(analyze|query|SQL|CSV|how many|metrics|report|data file|show me the|dataset|aggregate|pivot|histogram)'; then
  AGENT="Albert Einstein (Analyst)"
elif printf '%s\n' "$PROMPT" | grep -qiE '(write a function|write a test|write a class|write a script|write a method|write a module|write a component|write a hook|write a handler|write a parser)'; then
  AGENT="Tony Stark (Engineer)"
elif printf '%s\n' "$PROMPT" | grep -qiE '(write|draft|blog|README|document|explain to|email|release notes|marketing|copywriting|prose)'; then
  AGENT="Ernest Hemingway (Writer)"
elif printf '%s\n' "$PROMPT" | grep -qiE '(design|architect|before we build|system design|how should I structure|ADR|architecture decision|diagram)'; then
  AGENT="Leonardo da Vinci (Architect)"
elif printf '%s\n' "$PROMPT" | grep -qiE '(plan|break down|estimate|how should I|should I use|should I go with|what.s the best approach|help me think|roadmap|prioritize|scope this)'; then
  AGENT="Sun Tzu (Strategist)"
elif printf '%s\n' "$PROMPT" | grep -qiE '(what is|how does|compare|difference between|research|best way to|explain.*concept|versus|trade.?off)'; then
  AGENT="Marie Curie (Scientist)"
elif printf '%s\n' "$PROMPT" | grep -qiE '(build|implement|add |add a |fix|create|refactor|write a function|write a test|make it|update the)'; then
  AGENT="Tony Stark (Engineer)"
fi

[ -z "$AGENT" ] && exit 0

echo "$AGENT" > "$ROUTE_FILE"

echo "[Supercharger] Agent: $AGENT" >&2

ROUTE_AGENT="$AGENT" python3 -c "
import json, os
agent = os.environ['ROUTE_AGENT']
print(json.dumps({
    'hookSpecificOutput': {
        'hookEventName': 'UserPromptSubmit',
        'additionalContext': f'[SUPERCHARGER ROUTING] Classified as: {agent}. Dispatch this agent with the Agent tool as your first action. Do not reason about it — just dispatch.'
    }
}))
"

exit 0
