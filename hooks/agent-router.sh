#!/usr/bin/env bash
# Claude Supercharger — Agent Router
# Event: UserPromptSubmit | Matcher: (none)
# Classifies each user prompt and injects a routing directive into
# Claude's context. Writes classification to .agent-classified for agent-gate.sh.

set -euo pipefail

SUPERCHARGER_DIR="$HOME/.claude/supercharger"
SCOPE_DIR="$SUPERCHARGER_DIR/scope"
mkdir -p "$SCOPE_DIR"

ROUTE_FILE="$SCOPE_DIR/.agent-classified"

_INPUT=$(cat)
PROMPT=$(printf '%s\n' "$_INPUT" | jq -r '.prompt // empty' 2>/dev/null)
if [ -z "$PROMPT" ]; then
  PROMPT=$(printf '%s\n' "$_INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('prompt',''))" 2>/dev/null || echo "")
fi

[ -z "$PROMPT" ] && exit 0

# Resolve project directory from hook JSON payload — $PWD is not reliable in hook context
PROJECT_DIR=$(printf '%s\n' "$_INPUT" | jq -r '.workspace.current_dir // .cwd // empty' 2>/dev/null)
[ -z "$PROJECT_DIR" ] && PROJECT_DIR="$PWD"

# Signal new prompt to statusline — delete cost marker so statusline saves fresh start cost
rm -f "$SCOPE_DIR/.prompt-cost" "$SCOPE_DIR/.prompt-tokens" "$SCOPE_DIR/.last-prompt-tokens"

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

[ -z "$AGENT" ] && AGENT="Steve Jobs (Generalist)"

echo "$AGENT" > "$ROUTE_FILE"

echo "[Supercharger] Agent: $AGENT" >&2

# Detect project agents in .claude/agents/ — prefer them over global classification
parse_agent_field() {
  local file="$1" field="$2"
  awk -v field="$field" 'BEGIN{in_fm=0}
    /^---/{in_fm++; next}
    in_fm==1 && $0 ~ ("^" field ":") {sub("^" field ":[[:space:]]*",""); print; exit}
    in_fm>=2{exit}' "$file" 2>/dev/null || echo ""
}

PROJECT_AGENTS_LIST=""
PROJECT_AGENTS_DIR="$PROJECT_DIR/.claude/agents"
if [ -d "$PROJECT_AGENTS_DIR" ]; then
  for agent_file in "$PROJECT_AGENTS_DIR"/*.md; do
    [ -f "$agent_file" ] || continue
    name=$(parse_agent_field "$agent_file" "name")
    name=$(printf '%s' "$name" | sed 's/[-_]/ /g' | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) tolower(substr($i,2)); print}')
    desc=$(parse_agent_field "$agent_file" "description")
    [ -z "$name" ] && continue
    # Truncate to first sentence, strip JSON-unsafe chars
    short_desc=$(printf '%s' "$desc" | sed 's/\. .*//' | tr -d '"\\')
    if [ -n "$PROJECT_AGENTS_LIST" ]; then
      PROJECT_AGENTS_LIST="${PROJECT_AGENTS_LIST}; ${name}: ${short_desc}"
    else
      PROJECT_AGENTS_LIST="${name}: ${short_desc}"
    fi
  done
fi

# Read active economy tier: prefer scope file, fall back to economy.md heading
TIER=""
ECONOMY_TIER_FILE="$SCOPE_DIR/.economy-tier"
if [ -f "$ECONOMY_TIER_FILE" ]; then
  TIER=$(cat "$ECONOMY_TIER_FILE" 2>/dev/null | tr -d '[:space:]')
fi
if [ -z "$TIER" ]; then
  ECONOMY_MD="$HOME/.claude/rules/economy.md"
  if [ -f "$ECONOMY_MD" ]; then
    TIER=$(grep -m1 '^### Active Tier:' "$ECONOMY_MD" 2>/dev/null | sed 's/^### Active Tier:[[:space:]]*//' | sed 's/[[:space:]].*//' | tr -d '[:space:]')
  fi
fi
[ -z "$TIER" ] && TIER="lean"

TIER_SUFFIX=" Active economy tier: ${TIER}. Maintain this verbosity level throughout your response."

if [ -n "$PROJECT_AGENTS_LIST" ]; then
  echo "[Supercharger] Project agents detected — will prefer over global" >&2
  CONTEXT="[SUPERCHARGER ROUTING] Classified as: ${AGENT}. Dispatch this agent with the Agent tool as your first action. Do not reason about it — just dispatch. Project agents available — these take precedence over global agents: ${PROJECT_AGENTS_LIST}. If any project agent fits the task, always prefer it over the global classification. If a project agent and global agent would both handle the same request, route to the project agent.${TIER_SUFFIX}"
else
  CONTEXT="[SUPERCHARGER ROUTING] Classified as: ${AGENT}. Dispatch this agent with the Agent tool as your first action. Do not reason about it — just dispatch.${TIER_SUFFIX}"
fi

CONTEXT_JSON=$(printf '%s' "$CONTEXT" | jq -Rs '.' 2>/dev/null || printf '"%s"' "$(printf '%s' "$CONTEXT" | tr -d '"\\' | tr '\n' ' ')")
printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":%s}}\n' "$CONTEXT_JSON"

exit 0
