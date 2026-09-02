#!/usr/bin/env bash
# Claude Supercharger — Locked line-range gate
# Event: PreToolUse | Matcher: Write,Edit,MultiEdit,NotebookEdit
#
# Asks before editing a line range a human deliberately locked, and quotes the
# REASON they recorded. Every other write guard here is path-granular —
# path-guard, critical-infra-guard, harness-tamper-guard all decide from the
# filename. This decides from the range inside the file, and carries the
# rationale of whoever locked it to whoever is about to change it.
#
# Opt-in by construction: the manifest is a file the user creates. With no
# manifest anywhere above the project this hook exits after two builtin tests
# and never forks, so people who do not use it pay nothing.
#
# Manifest: `.ai-locks` or `.vibetags-locks` (JSON Lines) at the project root or
# any ancestor. The schema is PIsberg/vibetags' verbatim, so a project already
# generating one is covered without conversion:
#
#     {"type":"locked","file":"src/a.py","startLine":10,"endLine":40,
#      "reason":"Step order is load-bearing; reordering skips regeneration"}
#
# ASK, never deny. Editing locked code is legitimate work — being unaware that
# it was locked is the problem. Same reasoning as the PR-merge tier in
# human-approval-gate: the act is fine, doing it unknowingly is not.
#
# Fails OPEN everywhere: no manifest, unreadable manifest, malformed lines, no
# python, unlocatable edit text. A lock manifest is documentation, and blocking
# work because documentation could not be parsed trains people to delete it.
# Disable: SUPERCHARGER_AI_LOCK_GUARD=0
set -uo pipefail

[ "${SUPERCHARGER_AI_LOCK_GUARD:-1}" = "0" ] && exit 0

HOOKS_DIR="${BASH_SOURCE[0]%/*}"
# Fork-free stdin read, same shape as the sibling guards.
IFS= read -r -d '' -t "${SUPERCHARGER_STDIN_TIMEOUT_S:-5}" _INPUT || [ $? -le 128 ] || _INPUT=""; _INPUT="${_INPUT%"${_INPUT##*[!$'\n']}"}"

# ZERO-FORK FAST PATH. Walk up from the working directory looking for a
# manifest. Nothing else in this file runs until one is found, so the cost for
# a project without locks is a handful of builtin `[ -f ]` tests.
#
# The gate is deliberately "does the manifest exist" and nothing more. A cheap
# pre-filter that models what the detector matches is the two-gate trap this
# repo has shipped SIX times — a rule written, tested against the detector, and
# unreachable because the gate never admitted the command. There is no pattern
# list here to drift out of sync.
_AL_MANIFEST=""
_AL_DIR="$PWD"
_AL_DEPTH=0
while [ -n "$_AL_DIR" ] && [ "$_AL_DEPTH" -lt 24 ]; do
  if [ -f "$_AL_DIR/.ai-locks" ]; then _AL_MANIFEST="$_AL_DIR/.ai-locks"; break; fi
  if [ -f "$_AL_DIR/.vibetags-locks" ]; then _AL_MANIFEST="$_AL_DIR/.vibetags-locks"; break; fi
  [ "$_AL_DIR" = "/" ] && break
  _AL_DIR="${_AL_DIR%/*}"
  [ -z "$_AL_DIR" ] && _AL_DIR="/"
  _AL_DEPTH=$((_AL_DEPTH + 1))
done
[ -n "$_AL_MANIFEST" ] || exit 0

# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh" 2>/dev/null || true
if command -v init_hook_suppress >/dev/null 2>&1; then
  init_hook_suppress "$PWD"
  check_hook_disabled "ai-lock-guard" && exit 0
fi

command -v python3 >/dev/null 2>&1 || exit 0

# v4.0.16: BASH converts the paths, python no longer tries to.
#
# Native Windows python resolves a leading-slash path against the CURRENT DRIVE,
# so an MSYS path reaches it as a path that does not exist. v4.0.15 tried to
# translate that in python and only handled the DRIVE-LETTER form (/c/... ->
# C:\...). Git Bash's other roots — /tmp, /home, /usr — are not drive letters:
# /tmp is really C:\Users\<user>\AppData\Local\Temp, and nothing in python can
# derive that, because it is the Git installation's mount table.
#
# The result was a fix that covered the production shape and not the test shape,
# so three CI cycles all reported the identical six failures. `cygpath -w` is the
# component that owns this mapping and ships with Git Bash; ask it instead of
# modelling it. Absent (every non-Windows platform), the paths pass through
# untouched and the detector's own fallback still handles the drive-letter form.
_AL_TARGET=$(printf '%s\n' "$_INPUT" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' 2>/dev/null || true)
if command -v cygpath >/dev/null 2>&1; then
  _AL_MANIFEST_N=$(cygpath -w -- "$_AL_MANIFEST" 2>/dev/null) || _AL_MANIFEST_N=""
  [ -n "$_AL_MANIFEST_N" ] && _AL_MANIFEST="$_AL_MANIFEST_N"
  if [ -n "$_AL_TARGET" ]; then
    _AL_TARGET_N=$(cygpath -w -- "$_AL_TARGET" 2>/dev/null) || _AL_TARGET_N=""
    [ -n "$_AL_TARGET_N" ] && _AL_TARGET="$_AL_TARGET_N"
  fi
fi

# `|| _AL_REASON=""` for the same reason safety.sh does it: any non-zero exit
# from the detector — missing file, crash, unreadable manifest — must degrade to
# allow, never to a deny with empty output. Unlike safety.sh, nothing here is
# python-only, because there is no bash-side arm: no output means no lock hit.
#
# AI_LOCK_DEBUG=1 makes the detector explain itself on stderr. Three CI cycles
# were spent guessing at a platform that cannot be run locally; the fourth should
# be able to answer rather than hint.
_AL_REASON=$(printf '%s' "$_INPUT" \
  | AI_LOCK_MANIFEST="$_AL_MANIFEST" AI_LOCK_TARGET="$_AL_TARGET" \
    python3 "$HOOKS_DIR/ai-lock-detect.py" 2>/dev/null) || _AL_REASON=""
[ -n "$_AL_REASON" ] || exit 0

# Ask once per file per session. An edit loop inside a locked range is a human
# who already said yes; asking every time is how a guard gets switched off.
_AL_STATE="${SUPERCHARGER_STATE:-${CLAUDE_PLUGIN_DATA:-$HOME/.claude/supercharger}}"
_AL_SID=$(printf '%s\n' "$_INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)
_AL_FILE=$(printf '%s\n' "$_INPUT" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' 2>/dev/null || true)
_AL_ACK="$_AL_STATE/scope/.ai-lock-ack-${_AL_SID:-nosession}"
if [ -n "$_AL_FILE" ] && [ -f "$_AL_ACK" ] && grep -qxF "$_AL_FILE" "$_AL_ACK" 2>/dev/null; then
  exit 0
fi
mkdir -p "$_AL_STATE/scope" 2>/dev/null || true
[ -n "$_AL_FILE" ] && printf '%s\n' "$_AL_FILE" >> "$_AL_ACK" 2>/dev/null || true

printf '%s' "$_AL_REASON" | python3 -c '
import json, sys
r = sys.stdin.read().strip()
msg = ("[Supercharger] LOCKED RANGE. " + r +
       "  Editing it is allowed — this asks once per file per session so the "
       "reason above is read first. Silence: SUPERCHARGER_AI_LOCK_GUARD=0")
print(json.dumps({"hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "ask",
    "permissionDecisionReason": msg}}))' 2>/dev/null || exit 0
exit 0
