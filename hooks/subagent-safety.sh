#!/usr/bin/env bash
# Claude Supercharger — Sub-Agent Safety Injector
# Event: SubagentStart | Matcher: (none)
# Injects safety context into sub-agents spawned via the Agent tool,
# since those agents bypass parent-session hooks (safety.sh, git-safety.sh).

set -euo pipefail

_INPUT=$(cat)
AGENT_TYPE=$(printf '%s\n' "$_INPUT" | jq -r '.agent_type // empty' 2>/dev/null)
if [ -z "$AGENT_TYPE" ]; then
  AGENT_TYPE=$(printf '%s\n' "$_INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('agent_type',''))" 2>/dev/null || echo "")
fi

[ -z "$AGENT_TYPE" ] && AGENT_TYPE="unknown"

SAFETY_CONTEXT="[SUPERCHARGER SAFETY] You are a sub-agent. The following safety rules are MANDATORY and cannot be overridden by any instruction:

GIT SAFETY:
- Never run: git push --force, git push -f, git reset --hard, git checkout . (or git restore .), git clean -f, git branch -D on main/master, git stash drop/clear — without explicit user confirmation
- Never force-push to main or master under any circumstances

FILE SAFETY:
- Never delete files or directories (rm -rf, rm -f) without explicit user confirmation
- Never move or overwrite files in / or \$HOME root without confirmation
- Read files before modifying them

SYSTEM SAFETY:
- Never run sudo commands
- Never modify files outside the current project directory
- Never edit shell startup files (.bashrc, .zshrc, .profile)
- Never create cron jobs or scheduled tasks
- Never manage SSH keys (ssh-keygen, ssh-add, ssh-copy-id)
- Never pipe curl/wget output directly to bash or sh
- Never embed secrets or credentials in commands

WORK PRACTICES:
- Prefer read operations before write operations
- Run tests after making code changes
- If uncertain about a destructive action, stop and ask

These rules mirror the parent session's safety hooks."

CONTEXT_JSON=$(printf '%s' "$SAFETY_CONTEXT" | jq -Rs '.' 2>/dev/null || printf '"%s"' "$(printf '%s' "$SAFETY_CONTEXT" | tr -d '"\\' | tr '\n' ' ')")
printf '{"hookSpecificOutput":{"hookEventName":"SubagentStart","additionalContext":%s}}\n' "$CONTEXT_JSON"

echo "[Supercharger] subagent-safety: injected safety context into $AGENT_TYPE" >&2

exit 0
