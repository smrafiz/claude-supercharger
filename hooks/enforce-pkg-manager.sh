#!/usr/bin/env bash
# Claude Supercharger — Package Manager Enforcement Hook
# Event: PreToolUse | Matcher: Bash
# Detects lockfiles and blocks the wrong package manager.

set -euo pipefail

# v2.x (HOOK-LATENCY-PLAN Phase 2): the only uninstrumented hot-path hook. Sourcing
# lib-timing installs the /perf EXIT-trap timing AND makes this advisory hook honor
# the /sc-off kill-switch (it exits at source time when disabled — previously it ran
# even with Supercharger off). No other behavior change.
HOOKS_DIR="${BASH_SOURCE[0]%/*}"
# shellcheck source=hooks/lib-timing.sh
. "$HOOKS_DIR/lib-timing.sh" 2>/dev/null || true

# v2.26.35: fork-free stdin read. `$(cat)` forks /bin/cat in EVERY hook —
# ~1.8ms each, and 18 blocking hooks fire per Bash tool call. The trailing
# strip reproduces $(cat)'s newline handling so this is byte-identical.
IFS= read -r -d '' _INPUT || true; _INPUT="${_INPUT%"${_INPUT##*[!$'\n']}"}"

# v2.6.16: bash fast-path before python3 fork. Most Bash commands don't touch
# npm/yarn/pip/bun at all — scan the raw stdin first. If none of those tokens
# appear, skip the python parse + cmd-normalize + segment walk entirely.
# Bench: dropped 90ms → 35ms (~-60%) for the common case (no package-manager
# token in the command). Hot-path savings since this fires on every Bash.
case "$_INPUT" in
  *npm*|*yarn*|*pip*|*bun*) ;;
  *) exit 0 ;;
esac

# v2.24.0: try a fork-free read first. Everything past the gate above used to pay a
# ~30ms python3 fork just to pull two strings, which made this the slowest hook in the
# PreToolUse:Bash wave (and with hooks running concurrently, the slowest hook sets the
# felt latency). lib-json-fast refuses anything ambiguous or escaped, so the python
# block below still runs verbatim whenever it can't be certain.
# shellcheck source=hooks/lib-json-fast.sh
. "$HOOKS_DIR/lib-json-fast.sh" 2>/dev/null || true

COMMAND=""; PROJECT_DIR=""; _FAST_OK=0
if command -v _json_fast_str >/dev/null 2>&1; then
  if _json_fast_str command "$_INPUT"; then
    COMMAND="$_JSON_FAST_VAL"
    if _json_fast_str cwd "$_INPUT"; then PROJECT_DIR="$_JSON_FAST_VAL"; fi
    _FAST_OK=1
  fi
fi

# Fallback: single python3 fork extracting both fields — replaces 2 jq + 2 python3.
# Output format: <command>\x1F<cwd>  (US separator, never appears in shell input)
# NB: `[ … ] || EXTRACTED=…` (not `&&`) — under `set -e` an `&&` whose test is false
# would make this the last command and exit 0 early.
if [ "$_FAST_OK" -eq 0 ]; then
  EXTRACTED=$(printf '%s\n' "$_INPUT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    cmd = ((d.get('tool_input') or {}).get('command') or '')
    cwd = d.get('cwd') or ''
    print(cmd + '\x1f' + cwd)
except Exception:
    print('\x1f')
" 2>/dev/null)
  COMMAND="${EXTRACTED%%$'\x1f'*}"
  PROJECT_DIR="${EXTRACTED#*$'\x1f'}"
fi

[ -z "$COMMAND" ] && exit 0
[ -z "$PROJECT_DIR" ] && PROJECT_DIR="$PWD"

source "${BASH_SOURCE[0]%/*}/cmd-normalize.sh"
CMD=$(normalize_cmd "$COMMAND")

# Per-segment view — protects against `safe && npm install` bypass.
SEGMENTS=$(split_segments "$CMD")
[ -z "$SEGMENTS" ] && SEGMENTS="$CMD"

block() {
  echo "" >&2
  echo "Supercharger blocked this command." >&2
  echo "  Reason : $1" >&2
  echo "  Command: $COMMAND" >&2
  echo "  This command is permanently blocked. Run it in your terminal directly if needed." >&2
  echo "" >&2
  RSN=$(printf '%s' "$1" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || printf '"%s"' "$1")
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":%s}}\n' "$RSN"
  exit 2
}

while IFS= read -r seg; do
  [ -z "$seg" ] && continue

  # pnpm project — block npm
  if [ -f "$PROJECT_DIR/pnpm-lock.yaml" ] && [ ! -L "$PROJECT_DIR/pnpm-lock.yaml" ]; then
    if [[ "$seg" =~ ^npm[[:space:]]+(install|run|exec|ci|start|test|build|add|remove|update|publish) ]]; then
      block "This project uses pnpm (pnpm-lock.yaml found). Use pnpm instead of npm."
    fi
  fi

  # yarn project — block npm install/add
  if [ -f "$PROJECT_DIR/yarn.lock" ] && [ ! -L "$PROJECT_DIR/yarn.lock" ]; then
    if [[ "$seg" =~ ^npm[[:space:]]+(install|ci|add|remove|update) ]]; then
      block "This project uses yarn (yarn.lock found). Use yarn instead of npm."
    fi
  fi

  # uv/poetry project — block raw pip install
  if { [ -f "$PROJECT_DIR/uv.lock" ] && [ ! -L "$PROJECT_DIR/uv.lock" ]; } || { [ -f "$PROJECT_DIR/poetry.lock" ] && [ ! -L "$PROJECT_DIR/poetry.lock" ]; }; then
    if [[ "$seg" =~ ^pip[[:space:]]+install ]]; then
      manager="uv"
      [ -f "$PROJECT_DIR/poetry.lock" ] && manager="poetry"
      block "This project uses $manager. Use '$manager add' instead of pip install."
    fi
  fi

  # bun project — block npm
  if { [ -f "$PROJECT_DIR/bun.lockb" ] && [ ! -L "$PROJECT_DIR/bun.lockb" ]; } || { [ -f "$PROJECT_DIR/bun.lock" ] && [ ! -L "$PROJECT_DIR/bun.lock" ]; }; then
    if [[ "$seg" =~ ^npm[[:space:]]+(install|run|exec|ci|start|test|build|add|remove|update) ]]; then
      block "This project uses bun (bun lockfile found). Use bun instead of npm."
    fi
  fi
done <<< "$SEGMENTS"

exit 0
