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
# A runner piped into tail/head/grep/tee without pipefail gets an ADVISORY (no
# prompt): the exit code is the filter's, but the output still shows the result.
# Disable: SUPERCHARGER_TEST_MASK_GUARD=0
set -uo pipefail
HOOKS_DIR="${BASH_SOURCE[0]%/*}"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh" 2>/dev/null || true

[ "${SUPERCHARGER_TEST_MASK_GUARD:-1}" = "0" ] && exit 0

# v2.26.35: fork-free stdin read. `$(cat)` forks /bin/cat in EVERY hook —
# ~1.8ms each, and 18 blocking hooks fire per Bash tool call. The trailing
# strip reproduces $(cat)'s newline handling so this is byte-identical.
. "${BASH_SOURCE[0]%/*}/lib-stdin.sh"
. "${BASH_SOURCE[0]%/*}/lib-deny.sh"; sc_read_input _INPUT

# Fast-path: needs both a verification-runner token AND an exit-mask token to be
# worth parsing. Superset of the precise patterns below, so it can't skip a match.
case "$_INPUT" in
  *test*|*jest*|*vitest*|*mocha*|*pytest*|*tsc*|*eslint*|*ruff*|*mypy*|*rspec*|*phpunit*|*rubocop*|*golangci*|*ctest*|*lint*|*typecheck*) : ;;
  *) exit 0 ;;
esac
# FAST-PATH GATE. This must admit everything _MASK can match, or the precise
# rule below is unreachable — the guard would look correct and never fire.
# v4.0.41 widened _MASK for `| true`, `|& true`, `&true`, `|| ( true )`,
# `|| { true; }` and `|| time true`, and the first attempt changed ONLY the
# regex: the matrix still showed misses because this glob rejected them first.
# Seventh instance of that shape in this project ([[two-gate-trap]]), in a rule
# that had just been tested.
#
# Kept as substring globs (cheap, no fork) but deliberately loose: a false
# admit here costs one regex evaluation, a false reject costs the whole guard.
case "$_INPUT" in
  *'|| true'*|*'|| :'*|*'||true'*|*'|| echo'*|*'||echo'*|*'exit 0'*|*'; true'*|*';true'*|*'; :'*) : ;;
  *'| true'*|*'|true'*|*'| :'*|*'|:'*|*'| echo'*|*'|echo'*) : ;;
  *'& true'*|*'&true'*|*'& :'*|*'&:'*) : ;;
  *'( true'*|*'{ true'*|*'(true'*|*'{true'*|*'time true'*|*'time :'*) : ;;
  *'| tail'*|*'|tail'*|*'| head'*|*'|head'*|*'| grep'*|*'|grep'*|*'| tee'*|*'|tee'*|*'|&'*) : ;;
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
_RUNNER_CORE='(^|[^a-zA-Z0-9_./-])((npm|yarn|pnpm|bun)[[:space:]]+(run[[:space:]]+)?(test|build|lint|typecheck|check|tsc)|jest|vitest|mocha|ava|pytest|py\.test|tox|nox|go[[:space:]]+test|cargo[[:space:]]+test|make[[:space:]]+(test|check|lint)|tsc|eslint|ruff|mypy|rspec|phpunit|rubocop|golangci-lint|gradle[[:space:]]+(test|check)|mvn[[:space:]]+(test|verify)|dotnet[[:space:]]+test|ctest)'
_RUNNER="$_RUNNER_CORE"'([^a-zA-Z0-9_-]|$)'
# The runner piped into an output filter IN THE SAME PIPELINE. Without pipefail the
# pipeline's status is the filter's: `pytest | tail -20` exits 0 when pytest fails.
# `[^;&|]` keeps the runner and the pipe in one pipeline (`npm test && git log | head`
# is not this), with `>&`/`&>` let through for `2>&1 | tail`. Idea from Himmel's
# block-tail-pipe-on-gates (github.com/yotamleo-org/Himmel, MIT); code our own.
_PIPE="$_RUNNER_CORE"'([[:space:]]([^;&|]|>&|&>)*)?\|&?[[:space:]]*(tail|head|grep|tee)([[:space:]]|$)'
# An exit-status mask. Every one of these makes a FAILING runner report success.
#
# v4.0.41 widened this from `|| true|:|echo` and `; exit 0|true|:` after testing
# ours against the evasion set enumerated by devanomaly/omama's work-order
# validator, which exists to reject a `verify:` step that cannot fail. Measured
# against the deployed hook — controls fired, so the misses were real:
#
#   pytest | true        exit status becomes true's        MISSED
#   pytest |& true       same, with stderr                 MISSED
#   pytest &true         runner backgrounded, true's exit  MISSED
#   pytest || ( true )   subshell hides the no-op          MISSED
#   pytest || { true; }  brace group, same                 MISSED
#   pytest || time true  `time` prefixes a no-op           MISSED
#
# NOT added, deliberately: `\true` and `'tr'"ue"` quote/backslash splicing. Those
# are deliberate-evasion shapes, and an agent willing to splice a token can edit
# the test file instead — the regex cost is real and the protection is not.
#
# NOT a mask, and must never fire (the over-block controls in the tests):
#   pytest && exit 0     `&&` short-circuits; a failure still exits non-zero
#   pytest || ! true     `! true` exits 1, so the failure survives
#   pytest || npm run x  a real fallback command is not a no-op
#   pytest | tee log     not a no-op, so no ASK; it still takes tee's status, which
#                        the pipe ADVISORY below reports instead
# The no-op must be a COMPLETE WORD. Without the trailing boundary, the `&`
# branch matched `&true=2` inside a query string and denied
# `curl "https://x?a=1&true=2" && pytest -q` — a real false positive, introduced
# while widening this rule and caught by the same fixture set that motivated the
# widening (omama ships `valid_amp_in_url.yaml` precisely for it). `=` is in the
# excluded class for that reason; `.`/`-`/`/` keep `true.sh`, `true-runner` and
# `/usr/bin/true-ish` from matching.
_NOOP='((true|:)([^a-zA-Z0-9_=./-]|$)|echo([[:space:]]|$))'
_MASK='(\|\|[[:space:]]*([({][[:space:]]*)?(time[[:space:]]+)?'"$_NOOP"\
'|\|&?[[:space:]]*'"$_NOOP"\
'|&[[:space:]]*'"$_NOOP"\
'|;[[:space:]]*(exit[[:space:]]+0|true|:)([[:space:]]|;|$))'

printf '%s\n' "$CMD" | grep -qE "$_RUNNER" || exit 0
_KIND=ask
if ! printf '%s\n' "$CMD" | grep -qE "$_MASK"; then
  case "$CMD" in *pipefail*|*PIPESTATUS*|*pipestatus*) exit 0 ;; esac
  printf '%s\n' "$CMD" | grep -qE "$_PIPE" || exit 0
  _KIND=pipe
fi

# Ask once per masked runner per session. 2026-11-10: the key was the WHOLE command,
# so an agent re-running the same `npm run lint || echo ok` beside a heredoc whose
# text changed each time was asked every time. Now the key is only the segments
# (split on ; && and newlines) that name a runner; the rest of the command is ignored.
SID=$(printf '%s\n' "$_INPUT" | jq -r '.session_id // empty' 2>/dev/null || true); [ -z "$SID" ] && SID="${CLAUDE_CODE_SESSION_ID:-default}"
_SEEN="${SUPERCHARGER_STATE:-$HOME/.claude/supercharger}/scope/.testmask-seen-${SID}"
_KEYSRC=$(printf '%s\n' "$CMD" | awk '{gsub(/&&|;/, "\n"); print}' | grep -E "$_RUNNER" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g' | sort -u)
[ -z "$_KEYSRC" ] && _KEYSRC="$CMD"
_KEY=$(printf '%s' "$_KEYSRC" | cksum 2>/dev/null | cut -d' ' -f1 || echo "$CMD")
if [ -f "$_SEEN" ] && grep -qxF "$_KEY" "$_SEEN" 2>/dev/null; then
  exit 0
fi
mkdir -p "$(dirname "$_SEEN")" 2>/dev/null || true
echo "$_KEY" >> "$_SEEN" 2>/dev/null || true

if [ "$_KIND" = pipe ]; then
  _sc_json_escape "Supercharger: this pipes a test/lint/build run into tail, head, grep or tee. Without pipefail the exit code is the filter's, so a failing run reports 0. Read the pass/fail line in the output rather than the exit code, or prefix set -o pipefail; (Disable: SUPERCHARGER_TEST_MASK_GUARD=0)"
  printf '{"systemMessage":"%s","hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"%s"}}\n' "$_SC_JSON" "$_SC_JSON"
  exit 0
fi

_MSG="This command runs a verification tool (test/lint/typecheck) but MASKS its exit status (e.g. || true, || echo, ; exit 0) — a failing check will report success, so a subsequent \"it passes\" claim would be unfounded. Remove the exit-mask and let the real status surface, or confirm this is intentional CI glue. (Disable: SUPERCHARGER_TEST_MASK_GUARD=0)"
sc_decision ask "$_MSG"
echo "[Supercharger] test-mask-guard: ASK on exit-masked verification command" >&2
exit 0
