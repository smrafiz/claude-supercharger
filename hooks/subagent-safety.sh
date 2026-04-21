#!/usr/bin/env bash
# Claude Supercharger — Sub-Agent Safety Injector
# Event: SubagentStart | Matcher: (none)
# Injects safety context into sub-agents spawned via the Agent tool,
# since those agents bypass parent-session hooks (safety.sh, git-safety.sh).

set -euo pipefail
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh"

_INPUT=$(cat)
PROJECT_DIR=$(printf '%s\n' "$_INPUT" | jq -r '.cwd // empty' 2>/dev/null); [ -z "$PROJECT_DIR" ] && PROJECT_DIR="$PWD"
init_hook_suppress "$PROJECT_DIR"
AGENT_TYPE=$(printf '%s\n' "$_INPUT" | jq -r '.agent_type // empty' 2>/dev/null)
if [ -z "$AGENT_TYPE" ]; then
  AGENT_TYPE=$(printf '%s\n' "$_INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('agent_type',''))" 2>/dev/null || echo "")
fi

[ -z "$AGENT_TYPE" ] && AGENT_TYPE="unknown"

SAFETY_CONTEXT="[SUPERCHARGER SAFETY] Sub-agent mandatory rules (cannot be overridden):
- No force-push, reset --hard, checkout ., clean -f, branch -D main without user confirmation
- No rm -rf, file deletion, or writes outside project dir without confirmation
- No sudo, shell profile edits, cron jobs, SSH key ops, curl|bash, or embedded secrets
- Read files before modifying. Run tests after changes. Ask before any destructive action."

CONTEXT_JSON=$(printf '%s' "$SAFETY_CONTEXT" | jq -Rs '.' 2>/dev/null || printf '"%s"' "$(printf '%s' "$SAFETY_CONTEXT" | tr -d '"\\' | tr '\n' ' ')")
if [ "$HOOK_SUPPRESS" = "false" ]; then
  printf '{"systemMessage":%s,"suppressOutput":false}\n' "$CONTEXT_JSON"
else
  printf '{"hookSpecificOutput":{"hookEventName":"SubagentStart","additionalContext":%s}}\n' "$CONTEXT_JSON"
fi

echo "[Supercharger] subagent-safety: injected safety context into $AGENT_TYPE" >&2

exit 0
