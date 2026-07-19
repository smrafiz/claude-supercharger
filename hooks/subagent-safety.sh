#!/usr/bin/env bash
# Claude Supercharger — Sub-Agent Safety Injector
# Event: SubagentStart | Matcher: (none)
# Injects safety context into sub-agents spawned via the Agent tool,
# since those agents bypass parent-session hooks (safety.sh, git-safety.sh).

set -euo pipefail
HOOKS_DIR="${BASH_SOURCE[0]%/*}"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh"

_INPUT=$(cat)
PROJECT_DIR=$(printf '%s\n' "$_INPUT" | jq -r '.cwd // .workspace.current_dir // empty' 2>/dev/null || true); [ -z "$PROJECT_DIR" ] && PROJECT_DIR="$PWD"
init_hook_suppress "$PROJECT_DIR"
# v2.7.12: SubagentStart sends subagent_id/subagent_type (NOT agent_id/agent_type
# — those are the SubagentStop spellings). Reading only agent_id here left it
# empty, so the report-pin path fell back to <session>-<ts>.md while the
# SubagentStop fallback wrote <agent_id>.md — the two never matched, silently
# defeating the report-pin (the v2.7.1 fallback was masking it). Read both.
AGENT_TYPE=$(printf '%s\n' "$_INPUT" | jq -r '.agent_type // .subagent_type // empty' 2>/dev/null || true)
[ -z "$AGENT_TYPE" ] && AGENT_TYPE="unknown"

SESSION_ID=$(printf '%s\n' "$_INPUT" | jq -r '.session_id // "default"' 2>/dev/null | tr -cd 'a-zA-Z0-9_-' | head -c 64 || true)
[ -z "$SESSION_ID" ] && SESSION_ID="default"
AGENT_ID=$(printf '%s\n' "$_INPUT" | jq -r '.agent_id // .subagent_id // empty' 2>/dev/null | tr -cd 'a-zA-Z0-9_-' | head -c 64 || true)
[ -z "$AGENT_ID" ] && AGENT_ID="$SESSION_ID-$(date +%s)"
SAFETY_FLAG="$SUPERCHARGER_STATE/scope/.subagent-safety-injected-${SESSION_ID}"
REPORT_DIR="$SUPERCHARGER_STATE/scope/subagent-reports"
REPORT_PATH="$REPORT_DIR/${AGENT_ID}.md"
mkdir -p "$REPORT_DIR" 2>/dev/null || true

# Report guidance. Injected every spawn. HISTORY: this used to instruct the
# subagent to Write its report to disk as its LAST tool call (v2.6.82, working
# around CC return-channel degradation #69970/#54323). That BACKFIRED — the
# file-write (or the agent's refusal of it) consumed the final-message slot, so
# the parent received a stub/meta-note instead of the findings, then redid the
# work. Recovery no longer depends on the agent: subagent-report-fallback.sh
# scrapes the transcript on SubagentStop regardless. So we now tell the agent the
# OPPOSITE — return findings inline, don't write a file — which fixes the common
# case; the scraper + subagent-report-notify.sh handle the degraded-channel case.
REPORT_PIN="[SUPERCHARGER] Your FINAL text message is your deliverable to the parent — return your COMPLETE findings there (all results, file paths, code references, in plain markdown). Do NOT write a report file, and do NOT end with a bare acknowledgement like \"Done\", \"Complete\", or a note about report files — the parent reads only your final message. Supercharger auto-saves your transcript as a backup, so a report file is never needed."

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
