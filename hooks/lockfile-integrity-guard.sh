#!/usr/bin/env bash
# Claude Supercharger — Lockfile Integrity Guard
# Event: PreToolUse | Matcher: Write,Edit,MultiEdit,NotebookEdit
#
# Dependency lockfiles are MACHINE-GENERATED — they encode a resolved dependency
# graph plus integrity hashes. Hand-editing one (to "fix" a merge conflict or bump
# a version without running the package manager) corrupts those hashes / the
# resolution, so `npm ci`/`yarn --frozen`/`cargo build --locked` then fail for
# everyone in CI, or silently install an inconsistent tree. The correct move is
# always to change the manifest and let the package manager regenerate the lock.
#
# This ASKS (not deny) — a deliberate manual merge-resolution is occasionally
# legitimate and a human can confirm — once per lockfile per session. enforce-pkg-
# manager is unrelated (it blocks the WRONG pm on the Bash channel; it never guards
# lockfile EDITS). Disable: SUPERCHARGER_LOCKFILE_GUARD=0
set -uo pipefail

HOOKS_DIR="${BASH_SOURCE[0]%/*}"
_SC_STATE="${SUPERCHARGER_STATE:-${CLAUDE_PLUGIN_DATA:-$HOME/.claude/supercharger}}"
[ "${SUPERCHARGER_LOCKFILE_GUARD:-1}" = "0" ] && exit 0

# v2.26.35: fork-free stdin read. `$(cat)` forks /bin/cat in EVERY hook —
# ~1.8ms each, and 18 blocking hooks fire per Bash tool call. The trailing
# strip reproduces $(cat)'s newline handling so this is byte-identical.
IFS= read -r -d '' _INPUT || true; _INPUT="${_INPUT%"${_INPUT##*[!$'\n']}"}"
# Fast-path: bail with ZERO forks unless the payload could reference a lockfile.
# This is a superset of lib-lockfile's basename list (every lock name contains
# "lock", "shrinkwrap", or ".sum") — false positives just fall through to the
# precise is_lockfile_path check below; no real lockfile name is missed.
case "$_INPUT" in
  *lock*|*shrinkwrap*|*.sum*) ;;
  *) exit 0 ;;
esac

# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh"
# shellcheck source=hooks/lib-lockfile.sh
. "$HOOKS_DIR/lib-lockfile.sh"
PROJECT_DIR=$(printf '%s\n' "$_INPUT" | jq -r '.cwd // .workspace.current_dir // empty' 2>/dev/null || true); [ -z "$PROJECT_DIR" ] && PROJECT_DIR="$PWD"
init_hook_suppress "$PROJECT_DIR"
check_hook_disabled "lockfile-integrity-guard" && exit 0

FILE_PATH=$(printf '%s\n' "$_INPUT" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' 2>/dev/null || true)
[ -z "$FILE_PATH" ] && exit 0

BASE="${FILE_PATH##*/}"
is_lockfile_path "$FILE_PATH" || exit 0

# Which package manager owns it (for the corrective hint).
case "$BASE" in
  package-lock.json|npm-shrinkwrap.json) PM="npm install" ;;
  yarn.lock)          PM="yarn install" ;;
  pnpm-lock.yaml)     PM="pnpm install" ;;
  bun.lockb|bun.lock) PM="bun install" ;;
  Cargo.lock)         PM="cargo build" ;;
  composer.lock)      PM="composer update" ;;
  Gemfile.lock)       PM="bundle install" ;;
  poetry.lock)        PM="poetry lock" ;;
  Pipfile.lock)       PM="pipenv lock" ;;
  go.sum)             PM="go mod tidy" ;;
  *)                  PM="your package manager" ;;
esac

# Ask once per lockfile per session (don't nag on repeated touches).
SID=$(printf '%s\n' "$_INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)
ACK_FILE="$_SC_STATE/scope/.lockfile-ack-${SID:-nosession}"
if [ -f "$ACK_FILE" ] && grep -qxF "$FILE_PATH" "$ACK_FILE" 2>/dev/null; then
  exit 0
fi
mkdir -p "$_SC_STATE/scope" 2>/dev/null || true
printf '%s\n' "$FILE_PATH" >> "$ACK_FILE" 2>/dev/null || true

echo "" >&2
echo "Supercharger: '$BASE' is a machine-generated lockfile." >&2
echo "  Hand-editing it corrupts integrity hashes / the resolved graph — regenerate it with '$PM' instead (edit the manifest, not the lock)." >&2
echo "  Confirm only if this is a deliberate manual edit. (Asked once per lockfile per session.)" >&2
echo "" >&2

RSN=$(printf "'%s' is a machine-generated lockfile — hand-editing corrupts integrity hashes/resolution; regenerate with '%s' (change the manifest, not the lock). Confirm only if this manual edit is intended." "$BASE" "$PM" \
  | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || printf '"lockfile edit — regenerate via the package manager instead"')
printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":%s}}\n' "$RSN"
exit 0
