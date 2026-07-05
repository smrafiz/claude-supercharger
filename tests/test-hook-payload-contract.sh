#!/usr/bin/env bash
# Meta-tests guarding recurring CC-payload drift classes across ALL hooks, so a
# fix that landed once (v2.6.57 cwd dual-field; v2.7.30 exit_code) can't silently
# regress in a later hook or a perf-sweep consolidation (which is exactly how
# bash-output-compactor + repetition-detector reacquired the cwd bug, v2.7.59).
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

HOOKS="$REPO_DIR/hooks"

echo "=== Hook Payload Contract Meta-Tests ==="

# v2.6.57: CC 2.1.176+ sometimes delivers the working dir in workspace.current_dir
# instead of .cwd. Every hook that reads .cwd for PROJECT_DIR must carry the
# fallback, or it silently mis-scopes to the (unreliable) hook-process $PWD.
begin_test "payload-contract: every .cwd field read has the workspace.current_dir fallback"
OFFENDERS=""
for f in "$HOOKS"/*.sh; do
  while IFS= read -r line; do
    [ -n "$line" ] && OFFENDERS="${OFFENDERS}  $(basename "$f"): ${line}"$'\n'
  done < <(grep -nE '\.cwd\b' "$f" 2>/dev/null \
             | grep -vE '^[0-9]+:[[:space:]]*#' \
             | grep -vE 'workspace\.current_dir' \
             | grep -E 'jq|python3|// ')
done
if [ -z "$OFFENDERS" ]; then
  pass
else
  fail "cwd reads missing '// .workspace.current_dir' fallback:"$'\n'"$OFFENDERS"
fi

# v2.7.30: PostToolUse Bash tool_response has NO exit_code field (it is
# {interrupted,isImage,noOutputExpected,stderr,stdout}). Any hook keying success
# off tool_response.exit_code logs every command as success — a silent no-op.
begin_test "payload-contract: no hook reads the nonexistent tool_response.exit_code"
OFFENDERS=""
for f in "$HOOKS"/*.sh; do
  while IFS= read -r line; do
    [ -n "$line" ] && OFFENDERS="${OFFENDERS}  $(basename "$f"): ${line}"$'\n'
  done < <(grep -nE 'tool_response.{0,3}exit_code|tool_response\[.exit_code' "$f" 2>/dev/null \
             | grep -vE '^[0-9]+:[[:space:]]*#')
done
if [ -z "$OFFENDERS" ]; then
  pass
else
  fail "hook reads tool_response.exit_code (does not exist on PostToolUse Bash):"$'\n'"$OFFENDERS"
fi

# v2.7.61: the live CC binary REJECTS hookSpecificOutput on PostCompact/PreCompact
# ("(root): Invalid input") — its schema allows hookSpecificOutput only for
# PreToolUse/UserPromptSubmit/PostToolUse/PostToolBatch/Stop/SubagentStop. A compact
# hook must emit raw text or top-level systemMessage. post-compact-inject shipped
# the invalid JSON for ~30 releases (v2.7.30) and silently dropped the restored
# context every compaction. Guard it: no compact-lifecycle hook emits hookSpecificOutput.
begin_test "payload-contract: PreCompact/PostCompact hooks don't emit hookSpecificOutput"
OFFENDERS=""
for f in "$HOOKS"/post-compact-inject.sh "$HOOKS"/precompact-priorities.sh "$HOOKS"/compaction-backup.sh; do
  [ -f "$f" ] || continue
  while IFS= read -r line; do
    [ -n "$line" ] && OFFENDERS="${OFFENDERS}  $(basename "$f"): ${line}"$'\n'
  done < <(grep -nE 'hookSpecificOutput' "$f" 2>/dev/null | grep -vE '^[0-9]+:[[:space:]]*#')
done
if [ -z "$OFFENDERS" ]; then
  pass
else
  fail "compact-lifecycle hook emits hookSpecificOutput (CC rejects it):"$'\n'"$OFFENDERS"
fi

report
