#!/usr/bin/env bash
# Claude Supercharger — Agent Router
# Event: UserPromptSubmit | Matcher: (none)
# Classifies each user prompt and injects a routing directive into
# Claude's context. Writes classification to .agent-classified for agent-gate.sh.

set -euo pipefail

SUPERCHARGER_DIR="$HOME/.claude/supercharger"
SCOPE_DIR="$SUPERCHARGER_DIR/scope"
mkdir -p "$SCOPE_DIR"

_INPUT=$(cat)
SESSION_ID=$(printf '%s\n' "$_INPUT" | jq -r '.session_id // empty' 2>/dev/null)
[ -z "$SESSION_ID" ] && SESSION_ID="default"

ROUTE_FILE="$SCOPE_DIR/.agent-classified-${SESSION_ID}"

PROMPT=$(printf '%s\n' "$_INPUT" | jq -r '.prompt // empty' 2>/dev/null)
if [ -z "$PROMPT" ]; then
  PROMPT=$(printf '%s\n' "$_INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('prompt',''))" 2>/dev/null || echo "")
fi

[ -z "$PROMPT" ] && exit 0

# Resolve project directory from hook JSON payload — $PWD is not reliable in hook context
PROJECT_DIR=$(printf '%s\n' "$_INPUT" | jq -r '.workspace.current_dir // .cwd // empty' 2>/dev/null)
[ -z "$PROJECT_DIR" ] && PROJECT_DIR="$PWD"

# Signal new prompt to statusline — delete cost marker so statusline saves fresh start cost
rm -f "$SCOPE_DIR/.prompt-cost-${SESSION_ID}" "$SCOPE_DIR/.prompt-tokens-${SESSION_ID}" "$SCOPE_DIR/.last-prompt-tokens-${SESSION_ID}"

AGENT=""

PROMPT_LOWER=$(printf '%s\n' "$PROMPT" | tr '[:upper:]' '[:lower:]')

# Ordered by specificity — most specific first
if [[ "$PROMPT_LOWER" =~ (error|exception|stack\ trace|not\ working|broken|failing|crash|null\ pointer|undefined\ is\ not|bug\ at\ line|segfault|traceback|exit\ code\ [0-9]) ]]; then
  AGENT="Sherlock Holmes (Detective)"
elif [[ "$PROMPT_LOWER" =~ (review|security\ issue|code\ smell|what\ do\ you\ think\ of|look\ at\ this|check\ my|critique|audit\ this|lgtm) ]]; then
  AGENT="Gordon Ramsay (Critic)"
elif [[ "$PROMPT_LOWER" =~ (analyze|query|sql|csv|how\ many|metrics|report|data\ file|show\ me\ the|dataset|aggregate|pivot|histogram) ]]; then
  AGENT="Albert Einstein (Analyst)"
elif [[ "$PROMPT_LOWER" =~ (write\ a\ function|write\ a\ test|write\ a\ class|write\ a\ script|write\ a\ method|write\ a\ module|write\ a\ component|write\ a\ hook|write\ a\ handler|write\ a\ parser) ]]; then
  AGENT="Tony Stark (Engineer)"
elif [[ "$PROMPT_LOWER" =~ (write|draft|blog|readme|document|explain\ to|email|release\ notes|marketing|copywriting|prose) ]]; then
  AGENT="Ernest Hemingway (Writer)"
elif [[ "$PROMPT_LOWER" =~ (design|architect|before\ we\ build|system\ design|how\ should\ i\ structure|adr|architecture\ decision|diagram) ]]; then
  AGENT="Leonardo da Vinci (Architect)"
elif [[ "$PROMPT_LOWER" =~ (plan|break\ down|estimate|how\ should\ i|should\ i\ use|should\ i\ go\ with|what.s\ the\ best\ approach|help\ me\ think|roadmap|prioritize|scope\ this) ]]; then
  AGENT="Sun Tzu (Strategist)"
elif [[ "$PROMPT_LOWER" =~ (what\ is|how\ does|compare|difference\ between|research|best\ way\ to|explain.*concept|versus|trade.?off) ]]; then
  AGENT="Marie Curie (Scientist)"
elif [[ "$PROMPT_LOWER" =~ (build|implement|add\ |add\ a\ |fix|create|refactor|write\ a\ function|write\ a\ test|make\ it|update\ the) ]]; then
  AGENT="Tony Stark (Engineer)"
fi

[ -z "$AGENT" ] && AGENT="Steve Jobs (Generalist)"

# Map agent names to task categories
case "$AGENT" in
  "Sherlock Holmes (Detective)")   CATEGORY="debugging" ;;
  "Gordon Ramsay (Critic)")        CATEGORY="review/critique" ;;
  "Albert Einstein (Analyst)")     CATEGORY="data analysis" ;;
  "Tony Stark (Engineer)")         CATEGORY="engineering/implementation" ;;
  "Ernest Hemingway (Writer)")     CATEGORY="writing/documentation" ;;
  "Leonardo da Vinci (Architect)") CATEGORY="architecture/design" ;;
  "Sun Tzu (Strategist)")          CATEGORY="planning/strategy" ;;
  "Marie Curie (Scientist)")       CATEGORY="research/investigation" ;;
  *)                               CATEGORY="general" ;;
esac

# Compact agent key for key=value output
case "$AGENT" in
  "Sherlock Holmes (Detective)")   AGENT_KEY="detective" ;;
  "Gordon Ramsay (Critic)")        AGENT_KEY="critic" ;;
  "Albert Einstein (Analyst)")     AGENT_KEY="analyst" ;;
  "Tony Stark (Engineer)")         AGENT_KEY="engineer" ;;
  "Ernest Hemingway (Writer)")     AGENT_KEY="writer" ;;
  "Leonardo da Vinci (Architect)") AGENT_KEY="architect" ;;
  "Sun Tzu (Strategist)")          AGENT_KEY="strategist" ;;
  "Marie Curie (Scientist)")       AGENT_KEY="scientist" ;;
  *)                               AGENT_KEY="generalist" ;;
esac

echo "$AGENT" > "$ROUTE_FILE"

echo "[Supercharger] Agent: $AGENT" >&2

# Detect project agents in .claude/agents/ — prefer them over global classification
parse_agent_fields() {
  local file="$1"
  awk 'BEGIN{in_fm=0; name=""; desc=""}
    /^---/{in_fm++; next}
    in_fm==1 && /^name:/ {sub("^name:[[:space:]]*",""); name=$0}
    in_fm==1 && /^description:/ {sub("^description:[[:space:]]*",""); desc=$0}
    in_fm>=2{print name "\t" desc; exit}
    END{if(in_fm<2 && (name!="" || desc!="")) print name "\t" desc}' "$file" 2>/dev/null
}

PROJECT_AGENTS_LIST=""
PROJECT_AGENTS_DIR="$PROJECT_DIR/.claude/agents"
if [ -d "$PROJECT_AGENTS_DIR" ]; then
  for agent_file in "$PROJECT_AGENTS_DIR"/*.md; do
    [ -f "$agent_file" ] || continue
    IFS=$'\t' read -r name desc <<< "$(parse_agent_fields "$agent_file")"
    [ -z "$name" ] && continue
    name=$(printf '%s' "$name" | sed 's/[-_]/ /g' | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) tolower(substr($i,2)); print}')
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

# Track last-seen category and tier for suppression logic
LAST_CATEGORY_FILE="$SCOPE_DIR/.last-category-${SESSION_ID}"
LAST_TIER_FILE="$SCOPE_DIR/.last-tier-${SESSION_ID}"
LAST_CATEGORY=$(cat "$LAST_CATEGORY_FILE" 2>/dev/null || echo "")
LAST_TIER=$(cat "$LAST_TIER_FILE" 2>/dev/null || echo "")
echo "$CATEGORY" > "$LAST_CATEGORY_FILE"
echo "$TIER" > "$LAST_TIER_FILE"

# Build compact key=value context (#3: replace verbose natural language)
if [ -n "$PROJECT_AGENTS_LIST" ]; then
  echo "[Supercharger] Project agents detected — will prefer over global" >&2
  CONTEXT="[CTX] task=${CATEGORY} agent=${AGENT_KEY} project=${PROJECT_AGENTS_LIST} tier=${TIER}"
else
  CONTEXT="[CTX] task=${CATEGORY} agent=${AGENT_KEY} tier=${TIER}"
fi

# #1: Dedup — if identical to last injection, skip entirely
HASH=$(printf '%s' "$CONTEXT" | md5sum 2>/dev/null | cut -d' ' -f1 || printf '%s' "$CONTEXT" | md5 -q 2>/dev/null || echo "")
HASH_FILE="$SCOPE_DIR/.router-hash-${SESSION_ID}"
LAST_HASH=$(cat "$HASH_FILE" 2>/dev/null || echo "")
echo "$HASH" > "$HASH_FILE"

if [ -n "$HASH" ] && [ "$HASH" = "$LAST_HASH" ]; then
  exit 0  # Context unchanged — skip injection
fi

# #7: Category unchanged — only re-emit if tier changed (abbreviated form)
if [ -n "$LAST_CATEGORY" ] && [ "$CATEGORY" = "$LAST_CATEGORY" ] && [ "$TIER" != "$LAST_TIER" ]; then
  CONTEXT="[CTX] tier=${TIER}"
fi

CONTEXT_JSON=$(printf '%s' "$CONTEXT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read().rstrip()))" 2>/dev/null || printf '"%s"' "$(printf '%s' "$CONTEXT" | tr -d '"\\' | tr '\n' ' ')")
printf '{"systemMessage":%s,"suppressOutput":true}\n' "$CONTEXT_JSON"

exit 0
