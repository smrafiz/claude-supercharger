#!/usr/bin/env bash
# Claude Supercharger — Re-entry Loop Detector
# Event: UserPromptSubmit | Matcher: (none)
# Detects when system output (hook messages, [MEM], [CTX]) gets pasted back
# as user input — a sign of an infinite echo loop.

set -euo pipefail
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh"
[ "${SUPERCHARGER_ADVISORY_HOOKS:-1}" = "0" ] && exit 0

_INPUT=$(cat)
PROJECT_DIR=$(printf '%s\n' "$_INPUT" | jq -r '.cwd // empty' 2>/dev/null || true); [ -z "$PROJECT_DIR" ] && PROJECT_DIR="$PWD"
init_hook_suppress "$PROJECT_DIR"
hook_profile_skip "reentry-detector" && exit 0

# Extract user prompt text
PROMPT=$(printf '%s\n' "$_INPUT" | jq -r '.message // .prompt // empty' 2>/dev/null || true)
[ -z "$PROMPT" ] && exit 0

# Check for system markers in user prompt — these should never appear in real user input
MARKERS='^\[MEM\] |^\[CTX\] |^\[LEARNING\] |^\[SUPERCHARGER\] |\[Supercharger\]|"systemMessage"|"suppressOutput"|"additionalContext"|hookSpecificOutput'

if echo "$PROMPT" | grep -qE "$MARKERS"; then
  # Count how many markers are present — single match might be quoting, 2+ is a loop.
  # v2.6.42: awk emits exactly one number; `grep -c | || echo 0` doubled output
  # on zero matches and aborted `[ "$MATCH_COUNT" -ge 2 ]` under set -e. Same
  # shape as the v2.6.27/v2.6.38 fixes.
  MATCH_COUNT=$(echo "$PROMPT" | awk -v p="$MARKERS" 'BEGIN{IGNORECASE=0} match($0, p){c++} END{print c+0}')
  if [ "$MATCH_COUNT" -ge 2 ]; then
    MSG="[SUPERCHARGER] Re-entry loop detected: your prompt contains system-generated markers ([MEM], [CTX], hook output). This usually means hook output was pasted back as input. Clear context with /clear and re-type your prompt."
    MSG_JSON=$(printf '%s' "$MSG" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))")
    printf '{"systemMessage":%s,"suppressOutput":%s}\n' "$MSG_JSON" "$HOOK_SUPPRESS"
    echo "[Supercharger] reentry-detector: loop detected (${MATCH_COUNT} system markers in user prompt)" >&2
  fi
fi

exit 0
