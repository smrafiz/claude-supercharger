#!/usr/bin/env bash
# Claude Supercharger — Critical-infra write gate
# Event: PreToolUse | Matcher: Write,Edit,MultiEdit,NotebookEdit
#
# Forces an explicit human confirm before Claude edits a critical-infra file —
# CI/CD pipelines, container/deploy defs, DB migrations, or auth logic. These are
# the "Human review triggers" guardrails.md already documents; this makes them an
# ENFORCEMENT gate instead of advisory prose the model can skip past.
#
# It does NOT hard-block (these are legitimate files) — it emits permissionDecision
# "ask", so a real edit just needs one conscious yes. To stop it being swallowed by
# /sc-autopilot, lib-smart-approve also declines auto-approval for these paths (both
# read the same matcher, hooks/lib-critical-infra.sh — no drift). /sc-readonly's deny
# still beats this; safety.sh's hard blocks are unaffected.
#
# UX: asks at most ONCE per file per session (records an ack after asking) so an
# active edit loop on a workflow file isn't a nag — the human already consented to
# that file this session.
set -uo pipefail

# Fast-path: resolve state inline, no fork/source needed to bail on a non-critical path.
_SC_STATE="${SUPERCHARGER_STATE:-${CLAUDE_PLUGIN_DATA:-$HOME/.claude/supercharger}}"
# D2: dedicated kill-switch, for parity with its sibling guards
# (SUPERCHARGER_GIT_REMOTE_GUARD / _LOCKFILE_GUARD / _WEBFETCH_EGRESS).
[ "${SUPERCHARGER_CRITICAL_INFRA_GUARD:-1}" = "0" ] && exit 0

HOOKS_DIR="${BASH_SOURCE[0]%/*}"
_INPUT=$(cat)
# Fast-path: bail with ZERO forks unless the payload could reference a critical-infra
# file. Broad-substring superset of lib-critical-infra's matcher — false positives
# fall through to the precise is_critical_infra_path check below (e.g. "author.js"
# hits *auth* here but is correctly rejected there).
case "$_INPUT" in
  *workflows*|*gitlab-ci*|*circleci*|*pipelines*|*travis*|*drone*|*Jenkinsfile*|*jenkinsfile*|\
  *Dockerfile*|*dockerfile*|*Containerfile*|*compose*|*.tf*|*migrat*|*alembic*|*prisma*|\
  *auth*|*passport*|*.strategy*) ;;
  *) exit 0 ;;
esac

# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh"
# shellcheck source=hooks/lib-critical-infra.sh
. "$HOOKS_DIR/lib-critical-infra.sh"
PROJECT_DIR=$(printf '%s\n' "$_INPUT" | jq -r '.cwd // .workspace.current_dir // empty' 2>/dev/null || true); [ -z "$PROJECT_DIR" ] && PROJECT_DIR="$PWD"
init_hook_suppress "$PROJECT_DIR"
check_hook_disabled "critical-infra-guard" && exit 0

FILE_PATH=$(printf '%s\n' "$_INPUT" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' 2>/dev/null || true)
[ -z "$FILE_PATH" ] && exit 0

CATEGORY=$(is_critical_infra_path "$FILE_PATH") || exit 0

# Already confirmed this file this session? Don't nag.
SID=$(printf '%s\n' "$_INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)
ACK_FILE="$_SC_STATE/scope/.infra-ack-${SID:-nosession}"
if [ -f "$ACK_FILE" ] && grep -qxF "$FILE_PATH" "$ACK_FILE" 2>/dev/null; then
  exit 0
fi

# Record the ack now (best-effort) so repeated edits to this file don't re-prompt.
mkdir -p "$_SC_STATE/scope" 2>/dev/null || true
printf '%s\n' "$FILE_PATH" >> "$ACK_FILE" 2>/dev/null || true

echo "" >&2
echo "Supercharger: this edit touches a $CATEGORY file — a documented review trigger." >&2
echo "  $FILE_PATH" >&2
echo "  Confirm you meant to change it. (Asked once per file per session.)" >&2
echo "" >&2

RSN=$(printf 'Editing a %s file (%s) is a documented human-review trigger — confirm this change is intended. Asked once per file per session.' "$CATEGORY" "$FILE_PATH" \
  | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || printf '"critical-infra file edit — confirm"')
printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":%s}}\n' "$RSN"
exit 0
