#!/usr/bin/env bash
# Claude Supercharger — Shell Wrapper Guard
# Event: PreToolUse | Matcher: Bash
# Detects destructive commands hidden inside interpreter wrappers:
#   python -c "..." / node -e "..." / perl -e "..." / ruby -e "..." / dash -c "..." / ksh -c "..."
# Complements safety.sh (which catches direct rm/mv) and the bash/sh/zsh -c
# pattern that safety.sh already blocks. This adds the other interpreters.

set -uo pipefail
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh"

_INPUT=$(cat)
PROJECT_DIR=$(printf '%s\n' "$_INPUT" | jq -r '.cwd // empty' 2>/dev/null); [ -z "$PROJECT_DIR" ] && PROJECT_DIR="$PWD"
init_hook_suppress "$PROJECT_DIR"
check_hook_disabled "shell-wrapper-guard" && exit 0

COMMAND=$(printf '%s\n' "$_INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

# Fast-path: skip python3 fork if no interpreter -c/-e wrapper present.
case "$COMMAND" in
  *python*\ -c*|*python*\ -c\"*|*python*\ -c\'*) ;;
  *node\ -e*|*node\ -e\"*|*node\ -e\'*) ;;
  *perl\ -e*|*perl\ -e\"*|*perl\ -e\'*) ;;
  *ruby\ -e*|*ruby\ -e\"*|*ruby\ -e\'*) ;;
  *dash\ -c*|*ksh\ -c*|*fish\ -c*) ;;
  *) exit 0 ;;
esac

REASON=$(CMD="$COMMAND" python3 - <<'PYEOF' 2>/dev/null
import os, re

cmd = os.environ.get('CMD', '')

PATH_CONT = r'(?![/A-Za-z0-9._-])'
DANGEROUS_TARGET = (
    r'(?:/' + PATH_CONT
    + r'|/\*'
    + r'|~' + PATH_CONT
    + r'|\$HOME'
    + r'|\.\.' + PATH_CONT
    + r')'
)

DESTRUCT = [
    r'rm\s+-[a-zA-Z]*[rR][a-zA-Z]*[fF]?\s+' + DANGEROUS_TARGET,
    r'rm\s+-[a-zA-Z]*[fF][a-zA-Z]*[rR]?\s+' + DANGEROUS_TARGET,
    r'git\s+reset\s+--hard',
    r'git\s+clean\s+-[fdFD]+',
    r'git\s+checkout\s+\.',
    r'git\s+push\s+.*--force.*\b(main|master)\b',
    r'mkfs\.',
    r'dd\s+if=',
    r'>\s*/dev/sd',
    r'chmod\s+(-R\s+)?777\s+/',
    r':\(\)\s*\{\s*:\s*\|\s*:\s*&\s*\}\s*;\s*:',
]

INTERPRETERS = [
    (r'(?:^|[\s;&|])python[23]?(?:\.\d+)?\s+-c\s+', 'python -c'),
    (r'(?:^|[\s;&|])(?:perl|ruby)\s+-e\s+', 'perl/ruby -e'),
    (r'(?:^|[\s;&|])node\s+-e\s+', 'node -e'),
    (r'(?:^|[\s;&|])(?:dash|ksh|fish)\s+-c\s+', 'dash/ksh/fish -c'),
]

def has_destructive(s):
    for p in DESTRUCT:
        if re.search(p, s, re.IGNORECASE):
            return p
    return None

for wrap_re, label in INTERPRETERS:
    m = re.search(wrap_re, cmd)
    if not m:
        continue
    inner = cmd[m.end():]
    if inner and inner[0] in ("'", '"'):
        inner = inner[1:]
    if has_destructive(inner):
        print(f'destructive command hidden in {label} wrapper')
        break
PYEOF
)

if [ -n "$REASON" ]; then
  echo "" >&2
  echo "Supercharger blocked this command." >&2
  echo "  Reason : $REASON" >&2
  echo "  Command: ${COMMAND:0:120}" >&2
  echo "  This command is permanently blocked. Run it in your terminal directly if needed." >&2
  echo "" >&2
  RSN=$(printf '%s' "$REASON" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))")
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":%s}}\n' "$RSN"
  exit 2
fi

exit 0
