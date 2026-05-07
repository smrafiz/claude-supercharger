#!/usr/bin/env bash
# Claude Supercharger — Conventional Commit Checker
# Event: PreToolUse | Matcher: Bash
# Validates commit messages follow conventional commit format.

set -euo pipefail
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh"

_INPUT=$(cat)
PROJECT_DIR=$(printf '%s\n' "$_INPUT" | jq -r '.cwd // empty' 2>/dev/null); [ -z "$PROJECT_DIR" ] && PROJECT_DIR="$PWD"
init_hook_suppress "$PROJECT_DIR"
check_hook_disabled "commit-check" && exit 0

COMMAND=$(printf '%s\n' "$_INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
if [ -z "$COMMAND" ]; then
  COMMAND=$(printf '%s\n' "$_INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('command',''))" 2>/dev/null || echo "")
fi

if [ -z "$COMMAND" ]; then
  exit 0
fi

source "$(dirname "${BASH_SOURCE[0]}")/cmd-normalize.sh"
CMD=$(normalize_cmd "$COMMAND")

block() {
  echo "" >&2
  echo "Supercharger blocked this commit." >&2
  echo "  Reason : $1" >&2
  echo "  Command: $COMMAND" >&2
  echo "  Fix    : rewrite the commit message above and retry. Conventional Commits format:" >&2
  echo "           type(scope): description  or  type: description  or  type!: description (breaking)" >&2
  echo "           Valid types: feat, fix, chore, docs, style, refactor, test, perf, ci, build, revert" >&2
  echo "           Example   : feat(auth): add OAuth support" >&2
  echo "  Disable: if your project doesn't use Conventional Commits, run" >&2
  echo "           rm ~/.claude/supercharger/.conventional-commits  (or remove from install)" >&2
  echo "" >&2
  RSN=$(printf '%s' "$1" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || printf '"%s"' "$1")
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":%s}}\n' "$RSN"
  exit 2
}

# Find the first `git commit` segment (handles compound bypass like `safe && git commit ...`).
SEGMENTS=$(split_segments "$CMD")
[ -z "$SEGMENTS" ] && SEGMENTS="$CMD"
COMMIT_SEG=""
while IFS= read -r seg; do
  if printf '%s\n' "$seg" | grep -qE '^git commit([[:space:]]|$)'; then
    COMMIT_SEG="$seg"
    break
  fi
done <<< "$SEGMENTS"

if [ -z "$COMMIT_SEG" ]; then
  exit 0
fi

# Allow --amend commits (they may retain existing messages)
if printf '%s\n' "$COMMIT_SEG" | grep -qE '(^|[[:space:]])--amend([[:space:]]|$)'; then
  exit 0
fi

# Re-target message extraction at the commit segment, not the full compound command.
CMD="$COMMIT_SEG"

# Extract commit message — handles -m "...", -m '...', and HEREDOC $(cat <<'EOF'...) patterns
MSG=$(COMMIT_CMD="$CMD" python3 -c "
import os, re
cmd = os.environ['COMMIT_CMD']

# Try -m '...' or -m \"...\"
m = re.search(r\"-m\s+[\\\"'](.+?)[\\\"']\", cmd)
if m:
    print(m.group(1))
else:
    # Try HEREDOC: -m \"\$(cat <<'EOF' or <<EOF ... extract first non-empty line after
    heredoc = re.search(r\"<<'?EOF'?\s*\n(.+?)(\nEOF)?\", cmd, re.DOTALL)
    if heredoc:
        lines = [l.strip() for l in heredoc.group(1).splitlines() if l.strip()]
        if lines:
            print(lines[0])
        else:
            print('')
    else:
        print('')
" 2>/dev/null || echo "")

# No message found — nothing to validate (e.g. interactive commit)
if [ -z "$MSG" ]; then
  exit 0
fi

# Allow merge commits
if printf '%s\n' "$MSG" | grep -qE '^Merge '; then
  exit 0
fi

# Validate conventional commit format: type(scope): description  or  type: description
VALID_TYPES="feat|fix|chore|docs|style|refactor|test|perf|ci|build|revert"
if ! printf '%s\n' "$MSG" | grep -qE "^(${VALID_TYPES})(\([^)]+\))?!?: .+"; then
  block "commit message does not follow conventional commit format.
  Expected : type(scope): description  or  type: description  or  type!: description (breaking)
  Valid types: feat, fix, chore, docs, style, refactor, test, perf, ci, build, revert
  Examples  : feat(auth): add OAuth support
              fix: resolve null pointer in parser
              feat!: drop Node 16 support (breaking change)"
fi

exit 0
