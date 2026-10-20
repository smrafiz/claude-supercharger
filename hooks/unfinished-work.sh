#!/usr/bin/env bash
# Claude Supercharger — Unfinished Work
# Event: Stop (async), SessionStart | Matcher: (none)
#
# "I'll tell you when it finishes" breaks when the session or the machine dies
# first: on 2026-10-20 a release job died in a reboot and nothing said so. Claude
# Code's Stop payload lists what is still in flight (`background_tasks`,
# `session_crons`, per the hooks reference), so no guessing is needed:
#
#   Stop          snapshot the session's in-flight work to scope/.inflight-<sid>.json,
#                 or delete the snapshot when nothing is running. Stop fires every
#                 turn, so the snapshot is always the latest turn's state.
#   SessionStart  a snapshot left by an EARLIER session for this project means it
#                 ended with work still running and no later turn saw it finish.
#                 Name it once, then mark it seen.
#
# Measured before building: parsing the agent's own "I'll..." sentences instead was
# rejected (89% kept, detector 12.5% false positives). This reads only facts.
# Disable: SUPERCHARGER_UNFINISHED_WORK=0
set -uo pipefail
# shellcheck source=hooks/lib-timing.sh
. "${BASH_SOURCE[0]%/*}/lib-timing.sh" 2>/dev/null || true
[ "${SUPERCHARGER_UNFINISHED_WORK:-1}" = 0 ] && exit 0
HOOKS_DIR="${BASH_SOURCE[0]%/*}"
# shellcheck source=hooks/lib-paths.sh
. "$HOOKS_DIR/lib-paths.sh" 2>/dev/null || true
: "${SUPERCHARGER_STATE:=${CLAUDE_PLUGIN_DATA:-$HOME/.claude/supercharger}}"
# shellcheck source=hooks/lib-stdin.sh
. "$HOOKS_DIR/lib-stdin.sh"; sc_read_input _INPUT

printf '%s\n' "$_INPUT" | SCOPE="$SUPERCHARGER_STATE/scope" python3 "$HOOKS_DIR/unfinished_work.py" 2>/dev/null || exit 0
exit 0
