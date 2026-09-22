#!/usr/bin/env bash
# Claude Supercharger — decision emitter (shared)
# Sourced by every hook that returns a PreToolUse decision.
#
# WHY THIS EXISTS. What a hook prints as `permissionDecisionReason` is the ONLY
# part of a block the agent receives. The `Supercharger blocked …` banner and the
# "run it in your terminal" line that hooks write to stderr go to the human and
# never reach the model. Measured 2026-09-17 with a subagent probe: the subagent
# got `.env file access (.env) — credentials likely present` and nothing else —
# no attribution, no remedy. An agent that cannot tell a guard from a shell error
# retries blindly, which is the behaviour the guard exists to stop.
#
# So every decision goes through here and carries three things:
#   1. WHO   — "Supercharger:" so the agent knows this is policy, not a failure
#   2. WHAT  — the reason, unchanged from the calling hook
#   3. HOW   — a remedy naming the way through, when there is one
#
# Escaping is pure bash on purpose. The previous sites forked `python3 -c
# json.dumps` (~20ms) or `jq -Rs` (~6ms) to escape one short string; 85 and 49
# call sites respectively. A deny is rare, so this is not a hot path, but a guard
# that cannot emit its verdict because python is missing fails OPEN, and that is
# the outcome worth designing against.

# JSON-escape a string into $_SC_JSON. Handles the characters that actually turn
# up in a reason: quotes and backslashes from user-supplied paths and commands,
# and newlines from multi-line input. Other control characters are dropped rather
# than escaped — they carry no meaning in a reason and an unescaped one would
# produce invalid JSON, which the harness reads as "no decision" (fail-open).
_sc_json_escape() {
  local s="$1" out=""
  s="${s//\\/\\\\}"          # backslash FIRST, or it re-escapes the ones below
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  # strip remaining C0 control bytes
  out=$(printf '%s' "$s" | tr -d '\000-\010\013\014\016-\037')
  _SC_JSON="$out"
}

# sc_decision <deny|ask|allow> <reason> [remedy] [event]
sc_decision() {
  local decision="$1" reason="$2" remedy="${3:-}" event="${4:-PreToolUse}" msg
  msg="Supercharger: $reason"
  [ -n "$remedy" ] && msg="$msg  Way through: $remedy"
  _sc_json_escape "$msg"
  printf '{"hookSpecificOutput":{"hookEventName":"%s","permissionDecision":"%s","permissionDecisionReason":"%s"}}\n' \
    "$event" "$decision" "$_SC_JSON"
}

# sc_deny <reason> [remedy] [event]  — emits the decision AND exits 2.
# Exit 2 is what actually blocks; emitting without it is a decision the harness
# may not honour, and that split is how a guard ends up "firing" but allowing.
sc_deny() {
  sc_decision deny "$1" "${2:-}" "${3:-}"
  exit 2
}

# sc_ask <reason> [remedy] [event] — emits and exits 0. An ask must NOT exit 2:
# exit 2 is a hard block, and a confirm that blocks is a deny with extra steps.
sc_ask() {
  sc_decision ask "$1" "${2:-}" "${3:-}"
  exit 0
}
