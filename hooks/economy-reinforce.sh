#!/usr/bin/env bash
# Claude Supercharger — Economy Tier Reinforcement
# Event: UserPromptSubmit | Matcher: (none)
# Re-injects active economy tier rules every Nth prompt to prevent drift.
# Models lose tier instructions after context compression or long conversations.
# Adapted from caveman per-turn reinforcement pattern.

set -euo pipefail
HOOKS_DIR="${BASH_SOURCE[0]%/*}"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh"
# shellcheck source=hooks/lib-json-fast.sh
. "${BASH_SOURCE[0]%/*}/lib-json-fast.sh" 2>/dev/null || true

SCOPE_DIR="$SUPERCHARGER_STATE/scope"
mkdir -p "$SCOPE_DIR"

# v2.26.35: fork-free stdin read. `$(cat)` forks /bin/cat in EVERY hook —
# ~1.8ms each, and 18 blocking hooks fire per Bash tool call. The trailing
# strip reproduces $(cat)'s newline handling so this is byte-identical.
IFS= read -r -d '' -t "${SUPERCHARGER_STDIN_TIMEOUT_S:-5}" _INPUT || [ $? -le 128 ] || _INPUT=""; _INPUT="${_INPUT%"${_INPUT##*[!$'\n']}"}"
# Pre-initialised: if lib-json-fast is absent _json_get is undefined, and
# under `set -u` an unset var here is FATAL — which turned a missing lib
# into a fail-CLOSED block. Empty keeps the fail-open contract.
PROJECT_DIR=""
_json_get PROJECT_DIR cwd "$_INPUT" '.cwd // .workspace.current_dir // empty'
[ -z "$PROJECT_DIR" ] && PROJECT_DIR="$PWD"
init_hook_suppress "$PROJECT_DIR"

# Resolve current tier
TIER=""
ECONOMY_TIER_FILE="$SCOPE_DIR/.economy-tier"
if [ -f "$ECONOMY_TIER_FILE" ]; then
  TIER=$(cat "$ECONOMY_TIER_FILE" 2>/dev/null | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')
fi
if [ -z "$TIER" ]; then
  ECONOMY_MD="$HOME/.claude/rules/economy.md"
  if [ -f "$ECONOMY_MD" ]; then
    TIER=$(grep -m1 '^### Active Tier:' "$ECONOMY_MD" 2>/dev/null | sed 's/^### Active Tier:[[:space:]]*//' | sed 's/[[:space:]].*//' | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')
  fi
fi
[ -z "$TIER" ] && TIER="lean"

# Standard tier is verbose by default — no reinforcement needed
[ "$TIER" = "standard" ] && exit 0

# v4.1.8: fire on EVERY prompt. This hook's header has always claimed per-turn
# reinforcement; the gate it actually had gave it twice a session.
#
# It used to fire only after compaction, on the theory that SessionStart delivers
# the tier rules once and only a compaction can drop them. That theory is wrong
# about how instructions decay. The rules do not vanish, they get outweighed —
# ~12.5KB of prompt layer is loaded per session and 463 bytes of it ask for
# terseness, against four other resident rule files that ask for thorough
# reporting (see docs/ECONOMY-LAYER-2026-09-19.md). Re-stating them twice does
# not win that argument.
#
# Caveman (the per-turn pattern this hook's header credits) injects its contract
# on every UserPromptSubmit and gates on nothing at all. That is the pattern;
# this hook adapted it into a compaction trigger and lost the property that made
# it work. ~230 bytes/turn is the cost, which is well under what one re-read of a
# file costs when the tier is forgotten.
#
# Deliberately NOT gated on context pressure: the obvious trigger (context %) is
# not obtainable in a UserPromptSubmit hook — `context_window` is absent from the
# payload, which is the defect that left three sibling hooks inert for 62
# sessions. Do not reintroduce that dependency here.
#
# Off-switch: the standard one. `{"disableHooks": ["economy-reinforce"]}` in
# .supercharger.json, or add it to scope/.disabled-hooks. No bespoke knob.
#
# The session-scoped .memory-restored / .eco-reinforce-acked flags are gone with
# the gate. Their leak class (v2.7.47 — a global flag firing in every concurrent
# session) cannot recur, because no flag is read here any more.

# Build tier-specific reinforcement message
case "$TIER" in
  minimal)
    MSG="[ECONOMY:MINIMAL] Telegraphic. Bare deliverables. No ceremony/filler/restatement. Fragments OK. Code blocks only. OVERRIDE: use full clarity for security warnings + irreversible actions."
    ;;
  lean)
    MSG="[ECONOMY:LEAN] Concise. Lead with deliverable. No ceremony. Bullets over prose. OVERRIDE: use full clarity for security warnings + irreversible actions."
    ;;
  *)
    exit 0
    ;;
esac

echo "[Supercharger] economy-reinforce: tier=${TIER}" >&2

CONTEXT_JSON=$(printf '%s' "$MSG" | jq -Rs '.' 2>/dev/null || printf '"%s"' "$(printf '%s' "$MSG" | tr -d '"\\' | tr '\n' ' ')")
if [ "$HOOK_SUPPRESS" = "false" ]; then
  printf '{"systemMessage":%s,"suppressOutput":false}\n' "$CONTEXT_JSON"
else
  printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":%s}}\n' "$CONTEXT_JSON"
fi

exit 0
