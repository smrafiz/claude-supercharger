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
VALID_EVENTS="PreToolUse PostToolUse PostToolUseFailure PostToolBatch Notification
UserPromptSubmit UserPromptExpansion SessionStart SessionEnd Stop StopFailure
SubagentStart SubagentStop PreCompact PostCompact PermissionRequest
PermissionDenied Setup TeammateIdle TaskCreated TaskCompleted Elicitation
ElicitationResult ConfigChange WorktreeCreate WorktreeRemove InstructionsLoaded
CwdChanged FileChanged MessageDisplay"

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
BAD=$(python3 - "$REPO_DIR/hooks/hooks.json" <<'PYEOF'
import json, sys
valid = set("""PreToolUse PostToolUse PostToolUseFailure PostToolBatch Notification
UserPromptSubmit UserPromptExpansion SessionStart SessionEnd Stop StopFailure
SubagentStart SubagentStop PreCompact PostCompact PermissionRequest
PermissionDenied Setup TeammateIdle TaskCreated TaskCompleted Elicitation
ElicitationResult ConfigChange WorktreeCreate WorktreeRemove InstructionsLoaded
CwdChanged FileChanged MessageDisplay""".split())
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
_is_valid "DirectoryAdded" && fail "the valid set accepts an event Claude Code rejects" || pass

begin_test "the check accepts a real one"
_is_valid "PreToolUse" && pass || fail "the valid set rejects a real event"

report
