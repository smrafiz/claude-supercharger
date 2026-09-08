#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

HOOK="$REPO_DIR/hooks/test-mask-guard.sh"
export SUPERCHARGER_HOME="$REPO_DIR"

echo "=== Test Mask Guard Tests ==="

TMP=$(mktemp -d)
mkin() { CMD="$2" SID="s$3" python3 - "$1" <<'PY'
import json, os, sys
open(sys.argv[1], "w").write(json.dumps({"tool_name": "Bash",
    "tool_input": {"command": os.environ["CMD"]}, "session_id": os.environ["SID"]}))
PY
}
verdict() {
  SUPERCHARGER_STATE="$(mktemp -d)" bash "$HOOK" < "$1" > "$TMP/o" 2>/dev/null
  python3 -c "import json,sys;s=open(sys.argv[1]).read().strip();print('ASK' if s and json.loads(s)['hookSpecificOutput']['permissionDecision']=='ask' else 'ALLOW')" "$TMP/o"
}
n=0
check() { n=$((n+1)); mkin "$TMP/c$n.json" "$2" "$n"; begin_test "$1"; local g; g=$(verdict "$TMP/c$n.json"); [ "$g" = "$3" ] && pass || fail "expected $3 got $g — $2"; }

# --- should ASK: verification runner with a masked exit status ---
check "pytest || true"           'pytest -q || true'              ASK
check "npm test || echo"         'npm test || echo ok'           ASK
check "make test; exit 0"        'make test; exit 0'             ASK
check "go test ; true"           'go test ./... ; true'          ASK
check "yarn test || :"           'yarn test || :'                ASK
check "jest || echo"             'npx jest || echo passed'       ASK
check "cargo test || true"       'cargo test || true'            ASK
check "eslint || true"           'eslint . || true'              ASK
check "npm run typecheck||true"  'npm run typecheck || true'     ASK
check "mypy || true"             'mypy src || true'              ASK
check "chained && then || true"  'pytest && echo done || true'   ASK

# --- should ALLOW: unmasked runner, or a mask on a non-runner ---
check "plain pytest"             'pytest -q'                     ALLOW
check "plain npm test"           'npm test'                      ALLOW
check "runner with &&"           'npm test && echo done'         ALLOW
check "output suppress only"     'go test ./... 2>/dev/null'     ALLOW
check "rm || true (not runner)"  'rm foo || true'                ALLOW
check "ls || true"               'ls || true'                    ALLOW
check "git status; exit 0"       'git status; exit 0'            ALLOW
check "echo || true"             'echo hi || true'               ALLOW
check "make build (no mask)"     'make build'                    ALLOW

# --- dedup: same masked command asks once per session ---
SS=$(mktemp -d); mkin "$TMP/dd.json" 'pytest || true' 99
begin_test "asks first time"
first=$(SUPERCHARGER_STATE="$SS" bash "$HOOK" < "$TMP/dd.json" 2>/dev/null)
[ -n "$first" ] && pass || fail "expected ASK first"
begin_test "silent on repeat (dedup)"
second=$(SUPERCHARGER_STATE="$SS" bash "$HOOK" < "$TMP/dd.json" 2>/dev/null)
[ -z "$second" ] && pass || fail "expected SILENT repeat: $second"
rm -rf "$SS"

# --- kill switch + fail-open ---
begin_test "kill switch disables"
out=$(SUPERCHARGER_TEST_MASK_GUARD=0 bash "$HOOK" < "$TMP/c1.json" 2>/dev/null)
[ -z "$out" ] && pass || fail "expected SILENT when disabled"

begin_test "malformed json fails open"
out=$(printf '%s' 'not json {' | bash "$HOOK" 2>/dev/null)
[ -z "$out" ] && pass || fail "expected fail-open silence"

rm -rf "$TMP"

# --- v4.0.41: shell shapes that also mask an exit status ---------------------
# Widened after testing ours against the evasion set enumerated by
# devanomaly/omama's work-order validator, which exists to reject a `verify:`
# step that cannot fail. Its fixture names ARE the taxonomy: invalid_verify_
# pipe_true, _semi_true, _pipeamp_true, _time_true, _redir_word_true, and
# matching valid_* controls so the rule does not over-block.
#
# Two mistakes were made while adding this, both caught by the matrix:
#
#   1. The regex was widened and the FAST-PATH GLOB was not, so the new rule was
#      unreachable and the guard looked correct while firing on nothing. Seventh
#      instance of [[two-gate-trap]], in a rule that had just been tested.
#   2. The `&` branch matched `&true=2` inside a query string, denying
#      `curl "https://x?a=1&true=2" && pytest -q`. omama ships
#      valid_amp_in_url.yaml for exactly that; their fixture predicted the bug.
#      `_NOOP` now requires a word boundary, with `=` excluded by name.
_TMW_SC() {  # $1 = command -> FIRES | misses  (this guard ASKS: JSON on stdout)
  local st out
  st=$(mktemp -d); mkdir -p "$st/scope"
  out=$(printf '{"tool_name":"Bash","cwd":"/tmp","session_id":"w%s","tool_input":{"command":%s}}' \
        "$RANDOM" "$(printf '%s' "$1" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read()))')" \
        | SUPERCHARGER_STATE="$st" bash "$REPO_DIR/hooks/test-mask-guard.sh" 2>&1)
  rm -rf "$st"
  case "$out" in *permissionDecision*|*Supercharger*) printf 'FIRES' ;; *) printf 'misses' ;; esac
}

begin_test "mask: the existing shapes still fire (control)"
# Without this the widening could have deleted coverage and the rest would pass.
[ "$(_TMW_SC 'pytest -q || true')" = "FIRES" ] && [ "$(_TMW_SC 'pytest -q ; exit 0')" = "FIRES" ] \
  && pass || fail "the pre-existing masks stopped firing"

begin_test "mask: a pipe into a no-op is caught"
# `pytest | true` exits with true's status — the runner's result is discarded.
_TMW_BAD=""
for c in 'pytest -q | true' 'pytest -q |& true' 'pytest -q &true' \
         'pytest -q || time true' 'pytest -q || ( true )' 'pytest -q || { true; }'; do
  [ "$(_TMW_SC "$c")" = "FIRES" ] || _TMW_BAD="$_TMW_BAD [$c]"
done
[ -z "$_TMW_BAD" ] && pass || fail "missed:$_TMW_BAD"

begin_test "mask: the fast-path glob admits everything the regex matches"
# The rule is unreachable if the cheap gate rejects first. Assert the gate has
# grown alongside the regex rather than trusting that it did.
grep -q "\*'| true'\*" "$REPO_DIR/hooks/test-mask-guard.sh" \
  && grep -q "\*'( true'\*" "$REPO_DIR/hooks/test-mask-guard.sh" \
  && pass || fail "fast-path glob does not admit the widened shapes"

begin_test "mask: does NOT fire on an ampersand inside a URL"
# The false positive this widening introduced, and the reason _NOOP needs a
# word boundary.
[ "$(_TMW_SC 'curl "https://x/y?a=1&true=2" && pytest -q')" = "misses" ] \
  && pass || fail "query-string &true=2 read as an exit-status mask"

begin_test "mask: does NOT fire on shapes that preserve the failure"
# `&& exit 0` short-circuits on failure; `! true` exits 1; a real fallback
# command is not a no-op. Each of these keeps a failing run failing.
_TMW_FP=""
for c in 'pytest -q && exit 0' 'pytest -q || ! true' 'pytest -q || npm run test:fallback'; do
  [ "$(_TMW_SC "$c")" = "misses" ] || _TMW_FP="$_TMW_FP [$c]"
done
[ -z "$_TMW_FP" ] && pass || fail "over-blocked:$_TMW_FP"

report
