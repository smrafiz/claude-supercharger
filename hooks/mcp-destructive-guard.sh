#!/usr/bin/env bash
# Claude Supercharger — MCP destructive-operation guard
# Event: PreToolUse | Matcher: infrastructure / filesystem / git MCP servers
#
# These MCP servers act through STRUCTURED tool calls, not a shell command
# string, so safety.sh (Bash), git-safety.sh (`git *`), and path-guard
# (Write/Edit) never see them. A destructive op — delete a cloud resource, drop
# a k8s namespace, docker prune, remove/erase files, git hard-reset/clean — runs
# unguarded. This hook ASKS (user confirms) when the TOOL NAME carries a
# destructive verb. Advisory + fail-open; the safety floor for the shell channel
# is unaffected. Disable: SUPERCHARGER_MCP_DESTRUCTIVE_GUARD=0
set -uo pipefail
HOOKS_DIR="${BASH_SOURCE[0]%/*}"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh" 2>/dev/null || true

[ "${SUPERCHARGER_MCP_DESTRUCTIVE_GUARD:-1}" = "0" ] && exit 0

_INPUT=$(cat)
TOOL=$(printf '%s\n' "$_INPUT" | jq -r '.tool_name // empty' 2>/dev/null || true)
[ -z "$TOOL" ] && exit 0

check_hook_disabled "mcp-destructive-guard" 2>/dev/null && exit 0

LOW=$(printf '%s' "$TOOL" | tr '[:upper:]' '[:lower:]')

# Destructive verbs in the tool name. Narrow enough to avoid ordinary ops:
# bare `reset` (git soft reset) is NOT matched — only `*hard*reset*`/`*reset*hard*`;
# `remove`/`delete`/`terminate`/`destroy`/`prune`/`drop`/`erase`/`wipe`/`flush`/
# `purge`/`teardown`/`deprovision` are unambiguous; `force` covers force-push.
case "$LOW" in
  *delete*|*remove*|*terminate*|*destroy*|*prune*|*drop*|*erase*|*wipe*|*flush*|*purge*|*teardown*|*deprovision*|*hard*reset*|*reset*hard*|*force*push*|*force_push*|*clean_force*|*rmdir*)
    reason="destructive MCP operation '$TOOL' — infrastructure/filesystem/git MCP servers bypass the shell-channel guards (safety.sh / git-safety / path-guard). This deletes or force-overwrites a resource/data and is often irreversible. Confirm it is intended and targets the right environment."
    ;;
  *)
    exit 0 ;;
esac

RSN=$(printf '%s' "$reason" | jq -Rs '.' 2>/dev/null || printf '"%s"' "$reason")
printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":%s}}\n' "$RSN"
echo "[Supercharger] mcp-destructive-guard: ASK on $TOOL" >&2
exit 0
