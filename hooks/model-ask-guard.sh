#!/usr/bin/env bash
# Claude Supercharger — model ask guard (2026-11-23)
# Events: PreToolUse (Agent) | Stop
#
# Some users must not run certain models (default: Fable). This hook:
#  - PreToolUse Agent: ASKS when a subagent would run on a listed model, through the
#    call's `model` or the `model:` line of the agent's definition file.
#  - Stop: tells the user, once per session and model, when the session itself
#    answered on a listed model (no hook runs before `/model`, so this is the earliest).
# The Bash channel (`claude --model fable`, `claude-fable-*` in a script) is checked
# in safety.sh. The asks are never auto-approved, not even by /sc-autopilot full.
# List: SUPERCHARGER_MODEL_ASK (space or comma separated, default "fable"; empty = off).
# Advisory + fail-open. Disable: SUPERCHARGER_MODEL_ASK_GUARD=0
set -uo pipefail
HOOKS_DIR="${BASH_SOURCE[0]%/*}"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh" 2>/dev/null || true

[ "${SUPERCHARGER_MODEL_ASK_GUARD:-1}" = "0" ] && exit 0
LIST="${SUPERCHARGER_MODEL_ASK-fable}"
LIST="${LIST//,/ }"
[ -n "${LIST// /}" ] || exit 0

. "$HOOKS_DIR/lib-stdin.sh"
. "$HOOKS_DIR/lib-deny.sh"; sc_read_input _INPUT
check_hook_disabled "model-ask-guard" 2>/dev/null && exit 0

# listed <model string>: prints the first listed word it contains (case-insensitive).
listed() {
  local m w
  m=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  for w in $LIST; do
    w=$(printf '%s' "$w" | tr '[:upper:]' '[:lower:]')
    case "$m" in *"$w"*) printf '%s' "$w"; return 0 ;; esac
  done
  return 1
}

EVENT=$(printf '%s\n' "$_INPUT" | jq -r '.hook_event_name // empty' 2>/dev/null || true)

if [ "$EVENT" = "Stop" ]; then
  TP=$(printf '%s\n' "$_INPUT" | jq -r '.transcript_path // empty' 2>/dev/null || true)
  SID=$(printf '%s\n' "$_INPUT" | jq -r '.session_id // empty' 2>/dev/null | tr -cd 'A-Za-z0-9_-')
  [ -n "$TP" ] && [ -r "$TP" ] || exit 0
  # The newest assistant line names the model that just answered.
  M=$(tail -n 200 "$TP" 2>/dev/null | grep -o '"model":"[^"]*"' | grep -v '<synthetic>' | tail -n 1 | cut -d'"' -f4)
  [ -n "$M" ] || exit 0
  W=$(listed "$M") || exit 0
  F="${SUPERCHARGER_STATE:-$HOME/.claude/supercharger}/scope/.model-warned-${SID:-none}"
  grep -qxF -- "$M" "$F" 2>/dev/null && exit 0
  mkdir -p "${F%/*}" 2>/dev/null; printf '%s\n' "$M" >> "$F" 2>/dev/null || true
  _sc_json_escape "Supercharger: this session is answering on $M, which is on your ask list ($W). If you did not choose it, switch with /model now."
  printf '{"systemMessage":"%s"}\n' "$_SC_JSON"
  exit 0
fi

TOOL=$(printf '%s\n' "$_INPUT" | jq -r '.tool_name // empty' 2>/dev/null || true)
case "$TOOL" in Agent|Task) ;; *) exit 0 ;; esac

MODEL=$(printf '%s\n' "$_INPUT" | jq -r '.tool_input.model // empty' 2>/dev/null || true)
TYPE=$(printf '%s\n' "$_INPUT" | jq -r '.tool_input.subagent_type // empty' 2>/dev/null || true)
WHERE="the call's model setting"
if ! W=$(listed "$MODEL") && [ -n "$TYPE" ]; then
  # shortcut: plugin agents (plugin:name) are not looked up; add when a plugin ships one.
  CWD=$(printf '%s\n' "$_INPUT" | jq -r '.cwd // .workspace.current_dir // empty' 2>/dev/null || true)
  for d in "${CLAUDE_PROJECT_DIR:-$CWD}/.claude/agents" "$HOME/.claude/agents"; do
    [ -d "$d" ] || continue
    for f in "$d"/*.md; do
      [ -f "$f" ] || continue
      # The agent's name is its frontmatter `name:`, or else the file name.
      if [ "${f##*/}" = "$TYPE.md" ] || grep -qxF "name: $TYPE" "$f" 2>/dev/null; then
        AM=$(sed -n '1,/^---$/{/^model:/s/^model:[[:space:]]*//p;}' "$f" 2>/dev/null | head -n 1)
        if [ -n "$AM" ] && W=$(listed "$AM"); then MODEL="$AM"; WHERE="the agent file ${f/#$HOME/~}"; break 2; fi
      fi
    done
  done
fi
[ -n "${W:-}" ] || exit 0

SC_ASK_KEEP=1 sc_decision ask "this subagent would run on the model '$MODEL' (from $WHERE), which is on your ask list ($W)." "approve only if you chose this model; otherwise run it without that model"
echo "[Supercharger] model-ask-guard: ASK on $TOOL model $MODEL" >&2
exit 0
