#!/usr/bin/env bash
# Claude Supercharger — Write-time secret gate
# Event: PreToolUse | Matcher: Write,Edit,MultiEdit,NotebookEdit
#
# Asks before WRITING a credential into a file. The secret patterns were already
# applied to three channels — tool output (output-secrets-scanner), commits
# (commit-secret-guard) and prompts (prompt-secret-guard) — but never to the
# write itself. Measured against the installed harness before this existed: a
# private-key header, an AWS key and a GitHub token each written to an in-project
# file were allowed by all 160 hooks.
#
# That is the cross-channel parity class this repo keeps re-finding: sibling
# guards drift on WHICH TOOL CHANNEL they cover, not on what they look for.
#
# commit-secret-guard is a real backstop, so a written secret is still caught
# before it reaches git. Two things it cannot do: stop the value sitting in the
# working tree in the meantime, and see a file that is gitignored — a `.env`
# written by the agent never reaches a commit hook at all.
#
# ASK, never deny. Writing a key file is legitimate work — `.env.example`, a test
# fixture, a cert the user asked for. A hard block here would fire on all of them,
# and a guard that blocks legitimate work is one that gets switched off. Asks once
# per file per session, like its Write/Edit siblings.
# Disable: SUPERCHARGER_WRITE_SECRET_GUARD=0
set -uo pipefail

[ "${SUPERCHARGER_WRITE_SECRET_GUARD:-1}" = "0" ] && exit 0

HOOKS_DIR="${BASH_SOURCE[0]%/*}"
IFS= read -r -d '' -t "${SUPERCHARGER_STDIN_TIMEOUT_S:-5}" _INPUT || [ $? -le 128 ] || _INPUT=""; _INPUT="${_INPUT%"${_INPUT##*[!$'\n']}"}"
[ -n "$_INPUT" ] || exit 0

# shellcheck source=hooks/lib-secret-patterns.sh
. "$HOOKS_DIR/lib-secret-patterns.sh" 2>/dev/null || exit 0
[ "${#SECRET_PATTERNS[@]}" -gt 0 ] || exit 0
_WSG_RE=$(IFS='|'; echo "${SECRET_PATTERNS[*]}")

# GATE: the same pattern set, applied to the WHOLE payload. The payload is a
# strict superset of the content being written, so nothing the precise check
# below could match can fail this one — deliberately not a hand-written
# approximation of the patterns, which is the two-gate trap this repo has shipped
# six times. One grep, and it exits here for essentially every write.
printf '%s' "$_INPUT" | LC_ALL=C grep -qE "$_WSG_RE" 2>/dev/null || exit 0

# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh" 2>/dev/null || true
if command -v init_hook_suppress >/dev/null 2>&1; then
  init_hook_suppress "$PWD"
  check_hook_disabled "write-secret-guard" && exit 0
fi

# PRECISE: re-check only the text actually being written. The gate above matches
# the whole payload, which includes the file PATH and the tool name — a path like
# `~/keys/AKIA.../notes.md` would otherwise prompt on a write that carries no
# secret at all.
_WSG_NEW=$(printf '%s\n' "$_INPUT" | jq -r '
  [ .tool_input.content?,
    .tool_input.new_string?,
    .tool_input.new_source?,
    ( .tool_input.edits? // [] | .[]? | .new_string? )
  ] | map(select(. != null)) | join("\n")' 2>/dev/null || true)
[ -n "$_WSG_NEW" ] || exit 0
printf '%s' "$_WSG_NEW" | LC_ALL=C grep -qE "$_WSG_RE" 2>/dev/null || exit 0

_WSG_FILE=$(printf '%s\n' "$_INPUT" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' 2>/dev/null || true)
_WSG_SID=$(printf '%s\n' "$_INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)
_WSG_STATE="${SUPERCHARGER_STATE:-${CLAUDE_PLUGIN_DATA:-$HOME/.claude/supercharger}}"
_WSG_ACK="$_WSG_STATE/scope/.write-secret-ack-${_WSG_SID:-nosession}"
if [ -n "$_WSG_FILE" ] && [ -f "$_WSG_ACK" ] && grep -qxF "$_WSG_FILE" "$_WSG_ACK" 2>/dev/null; then
  exit 0
fi
mkdir -p "$_WSG_STATE/scope" 2>/dev/null || true
[ -n "$_WSG_FILE" ] && printf '%s\n' "$_WSG_FILE" >> "$_WSG_ACK" 2>/dev/null || true

# The VALUE is never echoed back. Repeating a credential into the transcript is
# the thing output-secrets-scanner exists to prevent, and this hook must not
# become the leak it guards against — name the file, not the match.
_WSG_BASE="${_WSG_FILE##*/}"
printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"[Supercharger] This write puts something matching a credential pattern into %s. If it is a real key it should live in an ignored env file or a secret store, not in a tracked file. If it is a placeholder or fixture, go ahead — this asks once per file per session. Silence: SUPERCHARGER_WRITE_SECRET_GUARD=0"}}\n' \
  "${_WSG_BASE:-the target file}"
exit 0
