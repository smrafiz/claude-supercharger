#!/usr/bin/env bash
# Claude Supercharger — Test Mask Guard
# Event: PreToolUse | Matcher: Bash
#
# Defends the flagship Verification Gate ("run the check, confirm it passes") at
# the COMMAND channel. Claude can make a failing check look green by masking the
# runner's EXIT status — `pytest -q || true`, `npm test || echo ok`,
# `make test; exit 0`, `go test ./... ; true` — after which a "tests pass" claim
# is unfounded. test-integrity-guard guards test-FILE edits and git-safety guards
# `--no-verify`; the command-level exit-mask on a verification runner was the
# unguarded sibling (cross-channel-parity-drift). ASKS (masking is occasionally
# legit in CI glue), once per command per session. NOTE: pure output suppression
# (`2>/dev/null` alone) is NOT flagged — it hides output but the exit code still
# propagates, so it can't turn red into green on its own. Advisory + fail-open;
# disable with SUPERCHARGER_TEST_MASK_GUARD=0.
# Disable: SUPERCHARGER_TEST_MASK_GUARD=0
set -uo pipefail
HOOKS_DIR="${BASH_SOURCE[0]%/*}"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh" 2>/dev/null || true

[ "${SUPERCHARGER_TEST_MASK_GUARD:-1}" = "0" ] && exit 0

# v2.26.35: fork-free stdin read. `$(cat)` forks /bin/cat in EVERY hook —
# ~1.8ms each, and 18 blocking hooks fire per Bash tool call. The trailing
# strip reproduces $(cat)'s newline handling so this is byte-identical.
IFS= read -r -d '' -t "${SUPERCHARGER_STDIN_TIMEOUT_S:-5}" _INPUT || [ $? -le 128 ] || _INPUT=""; _INPUT="${_INPUT%"${_INPUT##*[!$'\n']}"}"

# Fast-path: needs both a verification-runner token AND an exit-mask token to be
# worth parsing. Superset of the precise patterns below, so it can't skip a match.
case "$_INPUT" in
  *test*|*jest*|*vitest*|*mocha*|*pytest*|*tsc*|*eslint*|*ruff*|*mypy*|*rspec*|*phpunit*|*rubocop*|*golangci*|*ctest*|*lint*|*typecheck*) : ;;
  *) exit 0 ;;
esac
case "$_INPUT" in
  *'|| true'*|*'|| :'*|*'||true'*|*'|| echo'*|*'||echo'*|*'exit 0'*|*'; true'*|*';true'*|*'; :'*) : ;;
  *) exit 0 ;;
esac

check_hook_disabled "test-mask-guard" 2>/dev/null && exit 0
hook_profile_skip "test-mask-guard" 2>/dev/null && exit 0

CMD=$(printf '%s\n' "$_INPUT" | jq -r '.tool_input.command // .tool_input.script // empty' 2>/dev/null || true)
if [ -z "$CMD" ]; then
  CMD=$(printf '%s\n' "$_INPUT" | python3 -c "import sys,json;ti=json.load(sys.stdin).get('tool_input',{});print(ti.get('command') or ti.get('script') or '')" 2>/dev/null || echo "")
fi
[ -z "$CMD" ] && exit 0

# A verification runner (test / lint / typecheck / build).
_RUNNER='(^|[^a-zA-Z0-9_./-])((npm|yarn|pnpm|bun)[[:space:]]+(run[[:space:]]+)?(test|build|lint|typecheck|check|tsc)|jest|vitest|mocha|ava|pytest|py\.test|tox|nox|go[[:space:]]+test|cargo[[:space:]]+test|make[[:space:]]+(test|check|lint)|tsc|eslint|ruff|mypy|rspec|phpunit|rubocop|golangci-lint|gradle[[:space:]]+(test|check)|mvn[[:space:]]+(test|verify)|dotnet[[:space:]]+test|ctest)([^a-zA-Z0-9_-]|$)'
# An exit-status mask: `|| true|:|echo …`, or a trailing `; exit 0 / ; true / ; :`.
_MASK='(\|\|[[:space:]]*(true|:|echo)|;[[:space:]]*(exit[[:space:]]+0|true|:)([[:space:]]|;|$))'

printf '%s\n' "$CMD" | grep -qE "$_RUNNER" || exit 0
printf '%s\n' "$CMD" | grep -qE "$_MASK"   || exit 0

# Ask once per command per session (don't nag on a repeated identical command).
SID=$(printf '%s\n' "$_INPUT" | jq -r '.session_id // empty' 2>/dev/null || true); [ -z "$SID" ] && SID="${CLAUDE_CODE_SESSION_ID:-default}"
_SEEN="${SUPERCHARGER_STATE:-$HOME/.claude/supercharger}/scope/.testmask-seen-${SID}"
_KEY=$(printf '%s' "$CMD" | cksum 2>/dev/null | cut -d' ' -f1 || echo "$CMD")
if [ -f "$_SEEN" ] && grep -qxF "$_KEY" "$_SEEN" 2>/dev/null; then
  exit 0
fi
mkdir -p "$(dirname "$_SEEN")" 2>/dev/null || true
echo "$_KEY" >> "$_SEEN" 2>/dev/null || true

_MSG="This command runs a verification tool (test/lint/typecheck) but MASKS its exit status (e.g. || true, || echo, ; exit 0) — a failing check will report success, so a subsequent \"it passes\" claim would be unfounded. Remove the exit-mask and let the real status surface, or confirm this is intentional CI glue. (Disable: SUPERCHARGER_TEST_MASK_GUARD=0)"
RSN=$(printf '%s' "$_MSG" | jq -Rs '.' 2>/dev/null || printf '"%s"' "$_MSG")
printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":%s}}\n' "$RSN"
echo "[Supercharger] test-mask-guard: ASK on exit-masked verification command" >&2
exit 0
