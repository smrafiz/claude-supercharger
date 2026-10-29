#!/usr/bin/env bash
# Claude Supercharger — Trust Receipts
# Event: PostToolUse (async), SessionStart | Matcher: Bash,PowerShell,Artifact,ArtifactData,ArtifactComments,mcp__
#
# A local record of every action that left the machine and cannot be taken back:
# git/docker push, package publish, gh pr/issue/release writes, Artifact publish and
# delete, MCP tools whose name says send/post/create/share/upload/delete, and curl/
# wget/scp/rsync uploads. It never blocks: the egress and publish guards do that.
#
#   PostToolUse   append one receipt to receipts/YYYY-MM.jsonl, only for a call that
#                 ran. Holds kind, tool, destination and a one-line summary passed
#                 through lib-secret-patterns.sh. Never a message body.
#   SessionStart  name how many outward actions earlier sessions here took since the
#                 last start, once. Silent when there were none.
#
# Read them with /sc-receipts. Local only, never uploaded.
# Disable: SUPERCHARGER_RECEIPTS=0
set -uo pipefail
# shellcheck source=hooks/lib-timing.sh
. "${BASH_SOURCE[0]%/*}/lib-timing.sh" 2>/dev/null || true
[ "${SUPERCHARGER_RECEIPTS:-1}" = 0 ] && exit 0
HOOKS_DIR="${BASH_SOURCE[0]%/*}"
# shellcheck source=hooks/lib-paths.sh
. "$HOOKS_DIR/lib-paths.sh" 2>/dev/null || true
: "${SUPERCHARGER_STATE:=${CLAUDE_PLUGIN_DATA:-$HOME/.claude/supercharger}}"

# Read only the head of the payload: tool_name and tool_input come before the tool
# output, and a full bash read of a large output runs past the stdin timeout on Git
# Bash. Python gets the head plus the rest of stdin, so it still parses all of it.
_HEAD=""
IFS= read -r -d '' -n 65536 -t "${SUPERCHARGER_STDIN_TIMEOUT_S:-5}" _HEAD || [ -n "$_HEAD" ] || exit 0

# Cheap filter before any python fork: every outward kind names one of these words.
case "$_HEAD" in
  *SessionStart*|*push*|*publish*|*upload*|*'gh '*|*curl*|*wget*|*scp*|*rsync*|*mcp__*|*Artifact*) ;;
  *) exit 0 ;;
esac

OUTBOUND_SECRET_PATTERNS=""
# shellcheck source=hooks/lib-secret-patterns.sh
if . "$HOOKS_DIR/lib-secret-patterns.sh" 2>/dev/null; then
  IFS=$'\n'; OUTBOUND_SECRET_PATTERNS="${SECRET_PATTERNS[*]}"; unset IFS
fi
{ printf '%s' "$_HEAD"; cat; } | RECEIPTS="$SUPERCHARGER_STATE/receipts" \
  OUTBOUND_SECRET_PATTERNS="$OUTBOUND_SECRET_PATTERNS" PYTHONUTF8=1 \
  python3 "$HOOKS_DIR/trust_receipts.py" 2>/dev/null || exit 0
exit 0
