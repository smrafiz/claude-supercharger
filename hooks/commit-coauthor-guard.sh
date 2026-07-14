#!/usr/bin/env bash
# Claude Supercharger — Commit Co-Author Guard
# Event: PreToolUse | Matcher: Bash (git commit)
# OPT-IN, default OFF. Blocks `git commit` when the message carries a
# `Co-Authored-By:` trailer — i.e. the "Co-Authored-By: Claude …" AI-attribution
# line — for people who don't want AI attribution in their git history/blame.
# Enable per-machine:  touch ~/.claude/supercharger/scope/.coauthor-guard
# Enable per-session:  SUPERCHARGER_COAUTHOR_GUARD=1   (0 force-disables)
# Idea from domengabrovsek/claude (pre-commit-coauthor-gate.sh).

set -uo pipefail
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh"

# Enablement: explicit env 0 disables; else on if env=1 or the flag file exists.
_FLAG="$SUPERCHARGER_STATE/scope/.coauthor-guard"
case "${SUPERCHARGER_COAUTHOR_GUARD:-}" in
  0) exit 0 ;;
  1) ;;
  *) [ -f "$_FLAG" ] || exit 0 ;;
esac

_INPUT=$(cat)

# Fast-path: only `git commit` can matter.
case "$_INPUT" in *commit*) ;; *) exit 0 ;; esac

CMD=$(printf '%s\n' "$_INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)
if [ -z "$CMD" ]; then
  CMD=$(printf '%s\n' "$_INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('command',''))" 2>/dev/null || echo "")
fi
[ -z "$CMD" ] && exit 0

# Leave `git commit --help`/`-h` alone; only act on a real commit.
case "$CMD" in *"git commit --help"*|*"git commit -h"*) exit 0 ;; esac
printf '%s\n' "$CMD" | grep -qE '(^|[^a-zA-Z0-9_-])git[[:space:]]+commit([[:space:]]|$)' || exit 0

# Block any Co-Authored-By trailer (any case) — covers -m and inline heredocs.
if printf '%s\n' "$CMD" | grep -qiE 'co-authored-by:'; then
  echo "[Supercharger] commit-coauthor-guard: blocked AI attribution trailer" >&2
  REASON='This commit message contains a "Co-Authored-By:" trailer (AI attribution). The coauthor guard is enabled, which forbids AI attribution in commit history. Remove the Co-Authored-By line from the commit message and commit again. (Disable: SUPERCHARGER_COAUTHOR_GUARD=0, or rm ~/.claude/supercharger/scope/.coauthor-guard)'
  RSN=$(printf '%s' "$REASON" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || printf '"%s"' "$REASON")
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":%s}}\n' "$RSN"
  exit 2
fi

exit 0
