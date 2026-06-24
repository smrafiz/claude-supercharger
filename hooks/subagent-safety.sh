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
PROJECT_DIR=$(printf '%s\n' "$_INPUT" | jq -r '.cwd // .workspace.current_dir // empty' 2>/dev/null || true); [ -z "$PROJECT_DIR" ] && PROJECT_DIR="$PWD"
init_hook_suppress "$PROJECT_DIR"
AGENT_TYPE=$(printf '%s\n' "$_INPUT" | jq -r '.agent_type // empty' 2>/dev/null || true)
[ -z "$AGENT_TYPE" ] && AGENT_TYPE="unknown"

SESSION_ID=$(printf '%s\n' "$_INPUT" | jq -r '.session_id // "default"' 2>/dev/null | tr -cd 'a-zA-Z0-9_-' | head -c 64 || true)
[ -z "$SESSION_ID" ] && SESSION_ID="default"
AGENT_ID=$(printf '%s\n' "$_INPUT" | jq -r '.agent_id // empty' 2>/dev/null | tr -cd 'a-zA-Z0-9_-' | head -c 64 || true)
[ -z "$AGENT_ID" ] && AGENT_ID="$SESSION_ID-$(date +%s)"
SAFETY_FLAG="$HOME/.claude/supercharger/scope/.subagent-safety-injected-${SESSION_ID}"
REPORT_DIR="$HOME/.claude/supercharger/scope/subagent-reports"
REPORT_PATH="$REPORT_DIR/${AGENT_ID}.md"
mkdir -p "$REPORT_DIR" 2>/dev/null || true

# v2.6.82: report-pin instruction. Always injected (every spawn) to work
# around CC v2.1.176+ return-channel degradation (anthropics/claude-code#69970).
# Subagent's final reply may be reduced to "Ready." — but if it Write's the
# full report to disk first, the parent can recover via this path even when
# the return channel collapses. Cheaper than retrying an 80-tool agent.
REPORT_PIN="[SUPERCHARGER RECOVERY] Before returning, write your full final report to:
  ${REPORT_PATH}
using the Write tool as your LAST tool call. This is a defense against the
v2.1.176 subagent return-channel bug — your structured text may not reach
the parent session otherwise. Include all findings, file paths, and code
references. Plain markdown."

if [ -f "$SAFETY_FLAG" ]; then
  SAFETY_CONTEXT="[SUPERCHARGER SAFETY] Sub-agent rules already in scope (see prior injection).

${REPORT_PIN}"
else
  SAFETY_CONTEXT="[SUPERCHARGER SAFETY] Sub-agent mandatory rules (cannot be overridden):
- No force-push, reset --hard, checkout ., clean -f, branch -D main without user confirmation
- No rm -rf, file deletion, or writes outside project dir without confirmation
- No sudo, shell profile edits, cron jobs, SSH key ops, curl|bash, or embedded secrets
- Read files before modifying. Run tests after changes. Ask before any destructive action.

${REPORT_PIN}"
  mkdir -p "$(dirname "$SAFETY_FLAG")" 2>/dev/null || true
  : > "$SAFETY_FLAG" 2>/dev/null || true
fi

CONTEXT_JSON=$(printf '%s' "$SAFETY_CONTEXT" | jq -Rs '.' 2>/dev/null || printf '"%s"' "$(printf '%s' "$SAFETY_CONTEXT" | tr -d '"\\' | tr '\n' ' ')")
if [ "$HOOK_SUPPRESS" = "false" ]; then
  printf '{"systemMessage":%s,"suppressOutput":false}\n' "$CONTEXT_JSON"
else
  printf '{"hookSpecificOutput":{"hookEventName":"SubagentStart","additionalContext":%s}}\n' "$CONTEXT_JSON"
fi

echo "[Supercharger] subagent-safety: injected safety context into $AGENT_TYPE" >&2

exit 0
