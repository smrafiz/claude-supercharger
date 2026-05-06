#!/usr/bin/env bash
# Claude Supercharger — Git Safety Hook
# Event: PreToolUse | Matcher: Bash (git *)
set -euo pipefail
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh"

_INPUT=$(cat)
PROJECT_DIR=$(printf '%s\n' "$_INPUT" | jq -r '.cwd // empty' 2>/dev/null); [ -z "$PROJECT_DIR" ] && PROJECT_DIR="$PWD"
init_hook_suppress "$PROJECT_DIR"
COMMAND=$(printf '%s\n' "$_INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
if [ -z "$COMMAND" ]; then
  COMMAND=$(printf '%s\n' "$_INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('command',''))" 2>/dev/null || echo "")
fi

if [ -z "$COMMAND" ]; then
  exit 0
fi

source "$(dirname "${BASH_SOURCE[0]}")/cmd-normalize.sh"
CMD=$(normalize_cmd "$COMMAND")

# Per-segment view for ^-anchored git checks — protects against compound bypass
# like `safe && git push --force origin main`. Falls back to CMD if split fails.
SEGMENTS=$(split_segments "$CMD")
[ -z "$SEGMENTS" ] && SEGMENTS="$CMD"

block() {
  echo "" >&2
  echo "Supercharger blocked this git operation." >&2
  echo "  Reason : $1" >&2
  echo "  Command: $COMMAND" >&2
  echo "  This command is permanently blocked. Run it in your terminal directly if needed." >&2
  echo "" >&2
  local blocks_log="$HOME/.claude/supercharger/scope/.blocked-commands"
  mkdir -p "$(dirname "$blocks_log")" 2>/dev/null || true
  local safe_cmd="${COMMAND:0:120}"
  printf '[%s] %s — %s\n' "$(date '+%Y-%m-%d %H:%M')" "$1" "$safe_cmd" >> "$blocks_log" 2>/dev/null || true
  RSN=$(printf '%s' "$1" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || printf '"%s"' "$1")
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":%s}}\n' "$RSN"
  exit 2
}

rewrite() {
  local safe_cmd="$1" reason="$2"
  echo "[Supercharger] git-safety: rewrote unsafe command — ${reason}" >&2
  local cmd_json
  cmd_json=$(printf '%s' "$safe_cmd" | jq -Rs '.' 2>/dev/null || \
             printf '%s' "$safe_cmd" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null)
  if [ -z "$cmd_json" ]; then
    # Last-resort fallback: deny instead of emitting malformed JSON
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"git-safety: %s (rewriter unavailable, please run safely)"}}\n' "$reason"
    exit 2
  fi
  printf '{"hookSpecificOutput":{"updatedInput":{"command":%s}}}\n' "$cmd_json"
  exit 0
}

while IFS= read -r seg; do
  [ -z "$seg" ] && continue

  if [[ "$seg" =~ ^git\ push[[:space:]] ]]; then
    has_force=false
    has_protected=false

    if [[ "$seg" =~ (^|[[:space:]])(--force|--force-with-lease|-f)([[:space:]]|$) ]]; then
      has_force=true
    fi

    if [[ "$seg" =~ (^|[[:space:]])(main|master)([[:space:]]|$) ]]; then
      has_protected=true
    fi

    if $has_force && $has_protected; then
      block "force push to protected branch"
    elif $has_force; then
      # Non-protected branch — strip force flag, push safely.
      # Only rewrite when the whole command is the single git push (no compound).
      if [ "$CMD" = "$seg" ]; then
        safe=$(printf '%s\n' "$CMD" | sed -E 's/(^|[[:space:]])(--force-with-lease|--force|-f)([[:space:]]|$)/ /g' | tr -s ' ' | sed 's/[[:space:]]*$//')
        rewrite "$safe" "stripped --force from non-protected branch push"
      fi
    fi
  fi

  if [[ "$seg" =~ ^git\ reset[[:space:]] ]] && [[ "$seg" =~ (^|[[:space:]])--hard([[:space:]]|$) ]]; then
    block "git reset --hard can destroy uncommitted work"
  fi

  if [[ "$seg" =~ ^git\ (checkout|restore)[[:space:]]+(--[[:space:]]+)?\.([[:space:]]|$) ]]; then
    block "discards all unstaged changes"
  fi

  # git checkout <ref> -- .   /   git checkout <ref> .  → overwrites working tree from <ref>,
  # silently destroying unstaged work. Real-world loss reported in claude-code#55024.
  if [[ "$seg" =~ ^git\ checkout[[:space:]]+[^[:space:]-][^[:space:]]*[[:space:]]+(--[[:space:]]+)?\.([[:space:]]|$) ]]; then
    block "git checkout <ref> -- . overwrites all working-tree files from <ref>, destroying unstaged work"
  fi

  # git restore --source=<ref> .   → same destructive behavior via the modern restore syntax
  if [[ "$seg" =~ ^git\ restore[[:space:]] ]] && [[ "$seg" =~ --source[=[:space:]] ]] && [[ "$seg" =~ [[:space:]]\.([[:space:]]|$) ]]; then
    block "git restore --source=<ref> . overwrites working tree from <ref>, destroying unstaged work"
  fi

  if [[ "$seg" =~ ^git\ clean[[:space:]] ]] && [[ "$seg" =~ (^|[[:space:]])(--force|-f)([[:space:]]|$) ]]; then
    block "git clean with force permanently removes untracked files"
  fi

  if [[ "$seg" =~ ^git\ branch[[:space:]] ]] && [[ "$seg" =~ (^|[[:space:]])-D([[:space:]]|$) ]]; then
    if [[ "$seg" =~ (^|[[:space:]])(main|master)([[:space:]]|$) ]]; then
      block "force-deleting a protected branch (main/master)"
    fi
  fi

  if [[ "$seg" =~ ^git\ stash\ (drop|clear)([[:space:]]|$) ]]; then
    block "git stash drop/clear permanently removes stashed changes"
  fi
done <<< "$SEGMENTS"


# Checkpoint before commit — warn if unstaged/untracked work exists
if [[ "$CMD" =~ ^git\ commit([[:space:]]|$) ]]; then
  UNSTAGED=$(git diff --name-only 2>/dev/null | grep -v '^$' || true)
  UNTRACKED=$(git ls-files --others --exclude-standard 2>/dev/null | grep -v '^$' | head -10 || true)
  WARNINGS=()
  [ -n "$UNSTAGED" ] && WARNINGS+=("Unstaged changes: $(printf '%s' "$UNSTAGED" | tr '\n' ' ' | sed 's/ *$//')")
  [ -n "$UNTRACKED" ] && WARNINGS+=("Untracked files: $(printf '%s' "$UNTRACKED" | tr '\n' ' ' | sed 's/ *$//')")
  if [ ${#WARNINGS[@]} -gt 0 ]; then
    MSG="[CHECKPOINT] Committing with uncommitted work present. ${WARNINGS[*]} — confirm these are intentionally excluded."
    CONTEXT_JSON=$(printf '%s' "$MSG" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null \
      || printf '"%s"' "$(printf '%s' "$MSG" | tr -d '"\\' | tr '\n' ' ')")
    printf '{"systemMessage":%s,"suppressOutput":%s}\n' "$CONTEXT_JSON" "$HOOK_SUPPRESS"
    echo "[Supercharger] git-safety: checkpoint — unstaged/untracked work at commit time" >&2
  fi
fi

exit 0
