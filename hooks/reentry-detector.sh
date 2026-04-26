#!/usr/bin/env bash
# Claude Supercharger — Re-entry Loop Detector
# Event: UserPromptSubmit | Matcher: (none)
# Detects when system output (hook messages, [MEM], [CTX]) gets pasted back
# as user input — a sign of an infinite echo loop.

set -euo pipefail
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh"

_INPUT=$(cat)
PROJECT_DIR=$(printf '%s\n' "$_INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('cwd',''))" 2>/dev/null); [ -z "$PROJECT_DIR" ] && PROJECT_DIR="$PWD"
init_hook_suppress "$PROJECT_DIR"
hook_profile_skip "reentry-detector" && exit 0

# Extract user prompt text
PROMPT=$(printf '%s\n' "$_INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('message',''))" 2>/dev/null)
[ -z "$PROMPT" ] && exit 0

# Check for system markers in user prompt — these should never appear in real user input
MARKERS='^\[MEM\] |^\[CTX\] |^\[LEARNING\] |^\[SUPERCHARGER\] |\[Supercharger\]|"systemMessage"|"suppressOutput"|"additionalContext"|hookSpecificOutput'

if echo "$PROMPT" | grep -qE "$MARKERS"; then
  # Count how many markers are present — single match might be quoting, 2+ is a loop
  MATCH_COUNT=$(echo "$PROMPT" | grep -cE "$MARKERS" || echo "0")
  if [ "$MATCH_COUNT" -ge 2 ]; then
    MSG="[SUPERCHARGER] Re-entry loop detected: your prompt contains system-generated markers ([MEM], [CTX], hook output). This usually means hook output was pasted back as input. Clear context with /clear and re-type your prompt."
    MSG_JSON=$(printf '%s' "$MSG" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))")
    printf '{"systemMessage":%s,"suppressOutput":%s}\n' "$MSG_JSON" "$HOOK_SUPPRESS"
    echo "[Supercharger] reentry-detector: loop detected (${MATCH_COUNT} system markers in user prompt)" >&2
  fi
fi

exit 0
