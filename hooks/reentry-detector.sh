#!/usr/bin/env bash
# Claude Supercharger — Re-entry Loop Detector
# Event: UserPromptSubmit | Matcher: (none)
# Detects when system output (hook messages, [MEM], [CTX]) gets pasted back
# as user input — a sign of an infinite echo loop.

set -euo pipefail
HOOKS_DIR="${BASH_SOURCE[0]%/*}"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh"
# shellcheck source=hooks/lib-json-fast.sh
. "${BASH_SOURCE[0]%/*}/lib-json-fast.sh" 2>/dev/null || true
[ "${SUPERCHARGER_ADVISORY_HOOKS:-1}" = "0" ] && exit 0

# v2.26.35: fork-free stdin read. `$(cat)` forks /bin/cat in EVERY hook —
# ~1.8ms each, and 18 blocking hooks fire per Bash tool call. The trailing
# strip reproduces $(cat)'s newline handling so this is byte-identical.
IFS= read -r -d '' _INPUT || true; _INPUT="${_INPUT%"${_INPUT##*[!$'\n']}"}"
PROJECT_DIR=$(printf '%s\n' "$_INPUT" | jq -r '.cwd // .workspace.current_dir // empty' 2>/dev/null || true); [ -z "$PROJECT_DIR" ] && PROJECT_DIR="$PWD"
init_hook_suppress "$PROJECT_DIR"
hook_profile_skip "reentry-detector" && exit 0

# Extract user prompt text
# Pre-initialised: if lib-json-fast is absent _json_get is undefined, and
# under `set -u` an unset var here is FATAL — which turned a missing lib
# into a fail-CLOSED block. Empty keeps the fail-open contract.
PROMPT=""
_json_get PROMPT message "$_INPUT" '.message // .prompt // empty'
[ -z "$PROMPT" ] && exit 0

# Check for system markers in user prompt — these should never appear in real user input
MARKERS='^\[MEM\] |^\[CTX\] |^\[LEARNING\] |^\[SUPERCHARGER\] |\[Supercharger\]|"systemMessage"|"suppressOutput"|"additionalContext"|hookSpecificOutput'

if echo "$PROMPT" | grep -qE "$MARKERS"; then
  # Count how many markers are present — single match might be quoting, 2+ is a loop.
  # grep -oE emits one line per match; wc -l gives the count. Portable across
  # gawk/mawk/nawk. Uses the same MARKERS pattern as the outer grep -qE above.
  # v2.6.60: replaced awk match() — awk -v strips backslashes corrupting \[MEM\]
  # into character classes, and mawk does not support ERE alternation in match().
  MATCH_COUNT=$(printf '%s' "$PROMPT" | grep -oE "$MARKERS" | wc -l | tr -d ' ')
  if [ "$MATCH_COUNT" -ge 2 ]; then
    MSG="[SUPERCHARGER] Re-entry loop detected: your prompt contains system-generated markers ([MEM], [CTX], hook output). This usually means hook output was pasted back as input. Clear context with /clear and re-type your prompt."
    MSG_JSON=$(printf '%s' "$MSG" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))")
    printf '{"systemMessage":%s,"suppressOutput":%s}\n' "$MSG_JSON" "$HOOK_SUPPRESS"
    echo "[Supercharger] reentry-detector: loop detected (${MATCH_COUNT} system markers in user prompt)" >&2
  fi
fi

exit 0
