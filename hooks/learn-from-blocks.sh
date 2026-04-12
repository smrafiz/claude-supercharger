#!/usr/bin/env bash
# Claude Supercharger — Learn from Blocks
# Event: PreToolUse | Matcher: Bash
# When a command is blocked, log the pattern to learnings.md
# so Claude avoids it in future sessions.

set -euo pipefail

# This hook runs AFTER safety.sh / git-safety.sh via hook ordering.
# It reads stdin but only acts if the previous hook blocked (exit 2).
# Problem: we can't detect exit 2 from a sibling hook.
#
# Alternative approach: safety.sh and git-safety.sh write to a
# shared "last-block" file. This hook reads it on SessionStart
# and injects the learnings.

# This script is called from SessionStart, not PreToolUse.
# It reads accumulated blocks and injects them as context.

LEARNINGS_FILE="$HOME/.claude/supercharger/learnings.md"
BLOCKS_LOG="$HOME/.claude/supercharger/scope/.blocked-commands"

# If no blocks log, nothing to learn from
[ ! -f "$BLOCKS_LOG" ] && exit 0

BLOCK_COUNT=$(wc -l < "$BLOCKS_LOG" | tr -d ' ')
[ "$BLOCK_COUNT" -eq 0 ] && exit 0

# Read last 10 blocks
RECENT=$(tail -10 "$BLOCKS_LOG")

# Inject as context
CONTEXT="[LEARNINGS] These commands were blocked in recent sessions. Do not attempt them again:
${RECENT}
Avoid similar patterns. Use safe alternatives instead."

CONTEXT_JSON=$(printf '%s' "$CONTEXT" | jq -Rs '.' 2>/dev/null || printf '"%s"' "$(printf '%s' "$CONTEXT" | tr -d '"\\' | tr '\n' ' ')")
printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":%s}}\n' "$CONTEXT_JSON"

exit 0
