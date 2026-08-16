#!/usr/bin/env bash
# Every registered hook EVENT must be one Claude Code actually dispatches.
#
# A hook registered on an event the harness does not know is ignored in total
# silence: no error, no log line, no failing test. dir-added-record.sh sat on
# "DirectoryAdded" from v2.26.43 until a user's /doctor flagged it, so
# path-guard's in-session `/add-dir` support never worked — while
# test-additional-roots asserted the REGISTRATION existed and passed the whole
# time. Reading a registration proves it is WRITTEN, never that it FIRES.
#
# Third instance of this exact shape:
#   v2.24.5   a bare `mcp__` matcher matched nothing, killing 13 registrations
#   v2.26.85  an `if` field in the wrong dialect made two security guards inert
#   v2.27.x   an event name the harness does not dispatch
#
# The valid set is quoted from Claude Code's own error, which enumerates it when
# it rejects one. That is the authoritative source available to a test — the docs
# lag, and this repo has already been burned by trusting them over the harness.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

# Verbatim from: Unknown hook event "..." was ignored. Valid events: ...
# The valid set, preferring the INSTALLED Claude Code over anything hardcoded.
#
# A hardcoded list is a snapshot, and this file already went stale in the other
# direction: it asserted DirectoryAdded was INVALID, which was true when written
# and false once 2.1.219 shipped the event and 2.1.233 wired it to /add-dir. A
# list that can only rot is worse than one derived from the thing it describes.
#
# Claude Code exports one dispatcher per event (executeDirectoryAddedHooks,
# executePostToolBatchHooks, ...), so the binary names its own valid set. The
# fallback below is used when the binary cannot be located or read — it is the
# set as of CC 2.1.233, and DirectoryAdded is in it.
VALID_EVENTS=""
_CC_BIN=$(command -v claude 2>/dev/null || true)
if [ -n "$_CC_BIN" ]; then
  _CC_REAL=$(python3 -c "import os,sys; print(os.path.realpath(sys.argv[1]))" "$_CC_BIN" 2>/dev/null || true)
  if [ -n "$_CC_REAL" ] && [ -r "$_CC_REAL" ]; then
    VALID_EVENTS=$(strings "$_CC_REAL" 2>/dev/null \
      | grep -oE "execute[A-Za-z]+Hooks" \
      | sed 's/^execute//; s/Hooks$//' \
      | grep -vE "^(Hooks|HooksOutsideREPL)$" \
      | sort -u | tr "\n" " ")
    # Dispatchers are named PreTool/PostTool; the EVENTS are PreToolUse/PostToolUse.
    case "$VALID_EVENTS" in
      *"PreTool "*) VALID_EVENTS="$VALID_EVENTS PreToolUse PostToolUse SubagentStop" ;;
    esac
  fi
fi
# A derived set that came back implausibly small means the extraction broke, not
# that Claude Code lost its events — fall back rather than pass everything.
if [ "$(printf '%s' "$VALID_EVENTS" | wc -w | tr -d ' ')" -lt 10 ]; then
  VALID_EVENTS="PreToolUse PostToolUse PostToolUseFailure PostToolBatch Notification
UserPromptSubmit UserPromptExpansion SessionStart SessionEnd Stop StopFailure
SubagentStart SubagentStop PreCompact PostCompact PermissionRequest
PermissionDenied Setup TeammateIdle TaskCreated TaskCompleted Elicitation
ElicitationResult ConfigChange WorktreeCreate WorktreeRemove InstructionsLoaded
CwdChanged FileChanged MessageDisplay DirectoryAdded"
fi

_is_valid() {
  local e="$1" v
  for v in $VALID_EVENTS; do [ "$e" = "$v" ] && return 0; done
  return 1
}

echo "=== Hook Event Validity ==="

begin_test "every event in lib/hooks.sh is one Claude Code dispatches"
# shellcheck source=lib/hooks.sh
. "$REPO_DIR/lib/hooks.sh"
BAD=""
while IFS='|' read -r event _rest; do
  [ -n "$event" ] || continue
  _is_valid "$event" || BAD="$BAD $event"
done <<EOF
$(SUPERCHARGER_EMIT_ALL=1 get_hooks_for_mode "full" "true" '/h' 2>/dev/null)
EOF
[ -z "$BAD" ] && pass || fail "registered on event(s) Claude Code ignores — the hook never fires:$BAD"

begin_test "every event in the emitted plugin hooks.json is valid too"
# The plugin runtime reads this file, so a bad event there is inert for plugin
# users even if the installer path is clean. Both channels or neither.
# Prints OK, a list of bad events, or UNREADABLE. The last case matters: an
# earlier draft let json.load raise, which produced empty output and passed —
# a corrupted hooks.json would have been reported as clean. Caught when a
# mistaken redirect truncated the file mid-session.
# The valid set comes from $VALID_EVENTS — derived from the installed Claude Code
# above — NOT from a second hardcoded list. This block used to carry its own copy,
# and the two drifted the moment one was updated: the shell check accepted
# DirectoryAdded while this one still rejected it, in the same file.
BAD=$(SC_VALID="$VALID_EVENTS" python3 - "$REPO_DIR/hooks/hooks.json" <<'PYEOF'
import json, os, sys
valid = set(os.environ.get('SC_VALID', '').split())
if not valid:
    print('UNREADABLE: empty valid set'); raise SystemExit
try:
    d = json.load(open(sys.argv[1]))
except Exception as e:
    print('UNREADABLE: %s' % e); raise SystemExit
events = d.get('hooks') or {}
if not events:
    print('UNREADABLE: no hooks key'); raise SystemExit
bad = sorted(e for e in events if e not in valid)
print(' '.join(bad) if bad else 'OK')
PYEOF
)
[ "$BAD" = "OK" ] && pass || fail "hooks.json events: $BAD"

begin_test "the check actually rejects a bogus event (guard the guard)"
# A validator that cannot fail is worse than none — it reports clean forever.
# This briefly asserted DirectoryAdded instead, which left the property untested.
_is_valid "NotARealClaudeCodeEvent" && fail "the valid set accepts anything — it is not checking" || pass

begin_test "DirectoryAdded is accepted (Claude Code 2.1.219+ dispatches it)"
# This assertion used to read the other way and was correct then: the event did
# not exist, so the registration was inert. 2.1.219 added it and 2.1.233 wired it
# to /add-dir; the installed binary exports executeDirectoryAddedHooks. Pinning
# it in this direction is what makes the restored registration meaningful.
_is_valid "DirectoryAdded" && pass || fail "DirectoryAdded rejected — the derived set may have failed to extract"

begin_test "the check accepts a real one"
_is_valid "PreToolUse" && pass || fail "the valid set rejects a real event"

report
