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
  python3 -c "import json;s=open('$TMP/o').read().strip();print('ASK' if s and json.loads(s)['hookSpecificOutput']['permissionDecision']=='ask' else 'ALLOW')"
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
report
