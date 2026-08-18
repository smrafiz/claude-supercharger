#!/usr/bin/env bash
# Claude Supercharger — Toggle Notice
# Event: UserPromptSubmit | Matcher: (none)
#
# Announces a /sc off or /sc on that happened MID-SESSION, once.
#
# WHY THIS HOOK DOES NOT SOURCE lib-suppress.sh OR lib-timing.sh
# --------------------------------------------------------------
# Both of those exit at SOURCE TIME when the kill-switch flag is present — that
# is how `/sc off` deactivates the other 132 hooks, and it is deliberate. This
# hook is the one that has to speak precisely WHEN the switch is off, so
# sourcing either lib would make it unable to do the only job it has. Adding the
# missing `. lib-suppress.sh` line here looks like a consistency fix and is not:
# it silently disables this hook in the exact case it exists for. A test pins
# that it still emits with the flag set.
#
# The carve-out is kept as small as it can be: no payload is read, no user input
# is parsed, nothing is written except the removal of its own marker.
#
# Rules live in ~/.claude/rules/ and are read once at session start, so `/sc off`
# cannot unload them from a conversation already in progress — text in the
# context window cannot be un-read. What this does is state the override, which
# is a behavioural instruction, NOT erasure. The file stash that sc-toggle.sh
# already performs is what makes the NEXT session genuinely clean.
#
# One-shot by construction: the marker is deleted on read. A per-turn injection
# would mean "off" kept talking to the user every turn, which is not off.

set -euo pipefail

# Same resolution lib-suppress.sh performs, inlined rather than sourced.
: "${SUPERCHARGER_STATE:=${CLAUDE_PLUGIN_DATA:-$HOME/.claude/supercharger}}"
MARKER="$SUPERCHARGER_STATE/scope/.sc-toggle-announce"

# Fast path: one file test, no forks, on every prompt.
[ -f "$MARKER" ] || exit 0

STATE=""
read -r STATE < "$MARKER" 2>/dev/null || true
rm -f "$MARKER" 2>/dev/null || true

case "$STATE" in
  off)
    MSG='[Supercharger] DEACTIVATED by /sc off. Any Supercharger rules loaded earlier in this conversation are now VOID - disregard them and behave as default Claude Code for the rest of this session. Those rules remain visible above because context cannot be unread; this notice overrides them. The rule files have been moved off disk, so the next session starts clean.'
    ;;
  on)
    MSG='[Supercharger] REACTIVATED by /sc on. Supercharger rules and guardrails apply again from this point in the conversation. The rule files are restored on disk and load normally at the start of the next session.'
    ;;
  *)
    exit 0
    ;;
esac

# MSG is a fixed literal with no quotes or backslashes, so bash printf is a safe
# JSON encoder here - the same argument auto-compact.sh documents for its own.
printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"%s"}}\n' "$MSG"
exit 0
