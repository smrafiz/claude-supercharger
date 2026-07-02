#!/usr/bin/env bash
# Claude Supercharger — GitHub MCP Write Gate
# Event: PreToolUse | Matcher: mcp__github__*
#
# Blocks destructive autonomous writes via the GitHub MCP server. Real incident:
# Invariant Labs May 2025 — a malicious GitHub issue prompt-injected an agent
# into cross-repo exfil via public PR. The GitHub MCP exposes 80+ tool calls
# (push_files, create_or_update_file, delete_file, merge_pull_request,
# actions_run_trigger) with no built-in human-in-loop.
#
# This hook denies the highest-impact shapes:
#   - any push/write/delete targeting `main`/`master`/`production`
#   - merge_pull_request always (manual review required)
#   - delete_file on `.github/` or `*.yml`/`*.yaml`
#   - actions_run_trigger (privilege escalation surface)

set -euo pipefail
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh"

_INPUT=$(cat)
PROJECT_DIR=$(printf '%s\n' "$_INPUT" | jq -r '.cwd // .workspace.current_dir // empty' 2>/dev/null || true); [ -z "$PROJECT_DIR" ] && PROJECT_DIR="$PWD"
init_hook_suppress "$PROJECT_DIR"
check_hook_disabled "mcp-github-write-gate" && exit 0

TOOL=$(printf '%s\n' "$_INPUT" | jq -r '.tool_name // empty' 2>/dev/null || true)
case "$TOOL" in
  mcp__github__*) ;;
  *) exit 0 ;;
esac

deny() {
  local reason="$1"
  echo "" >&2
  echo "Supercharger blocked GitHub MCP write." >&2
  echo "  Tool   : $TOOL" >&2
  echo "  Reason : $reason" >&2
  echo "  Manual review required for high-impact GitHub operations." >&2
  echo "" >&2
  RSN=$(printf '%s' "$reason" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))")
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":%s}}\n' "$RSN"
  exit 2
}

# merge_pull_request — always require manual review
case "$TOOL" in
  *merge_pull_request*)
    deny "merge_pull_request requires manual review (no auto-merge in agentic context)"
    ;;
  *actions_run_trigger*|*trigger_workflow*)
    deny "GitHub Actions trigger blocked — workflow runs grant privileged execution"
    ;;
esac

# Extract branch + path fields from common tool_input shapes
BRANCH=$(printf '%s\n' "$_INPUT" | jq -r '.tool_input.branch // .tool_input.ref // empty' 2>/dev/null || true)
PATH_FIELD=$(printf '%s\n' "$_INPUT" | jq -r '.tool_input.path // empty' 2>/dev/null || true)

# Protected branch writes (push_files, create_or_update_file, delete_file)
if [ -n "$BRANCH" ]; then
  case "$BRANCH" in
    main|master|production|prod|release|release/*)
      deny "write to protected branch '$BRANCH' — open a PR instead"
      ;;
  esac
else
  # v2.7.41: an OMITTED branch defaults to the repo's DEFAULT branch (usually
  # main) — the highest-impact case, which previously skipped the check entirely.
  case "$TOOL" in
    *create_or_update_file*|*push_files*|*delete_file*)
      deny "write with no branch specified — GitHub defaults to the repo's default branch (usually main); target a feature branch or open a PR"
      ;;
  esac
fi

# delete_file on CI/sensitive paths
case "$TOOL" in
  *delete_file*)
    case "$PATH_FIELD" in
      .github/*|.github)
        deny "delete_file on .github/* — CI config changes need manual review"
        ;;
      *.yml|*.yaml)
        deny "delete_file on YAML config ($PATH_FIELD) — high blast radius"
        ;;
    esac
    ;;
esac

exit 0
