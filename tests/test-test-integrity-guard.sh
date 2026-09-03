#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

HOOK="$REPO_DIR/hooks/test-integrity-guard.sh"
export SUPERCHARGER_HOME="$REPO_DIR"

echo "=== Test Integrity Guard Tests ==="

TMP=$(mktemp -d)
# payload builder: emit tool_input JSON to a file, return its path
mk() { # name tool file_path old new  (for Write: old ignored, new=content)
  python3 - "$@" > "$TMP/$1.json" <<'PY'
import json,sys
name,tool,fp,old,new=sys.argv[1:6]
if tool=="Write":
    ti={"file_path":fp,"content":new}
elif tool=="MultiEdit":
    ti={"file_path":fp,"edits":[{"old_string":old,"new_string":new}]}
else:
    ti={"file_path":fp,"old_string":old,"new_string":new}
print(json.dumps({"tool_name":tool,"tool_input":ti}))
PY
  echo "$TMP/$1.json"
}
# does the hook ASK on this payload file?
asks() { bash "$HOOK" < "$1" 2>/dev/null | python3 -c "import sys,json
try: d=json.load(sys.stdin)
except Exception: sys.exit(1)
sys.exit(0 if d.get('hookSpecificOutput',{}).get('permissionDecision')=='ask' else 1)"; }

# 1. it.skip added
begin_test "asks when it.skip is added to a .test.js file"
J=$(mk t1 Edit /x/foo.test.js 'it("w", () => { expect(a).toBe(1); })' 'it.skip("w", () => { expect(a).toBe(1); })')
asks "$J" && pass || fail "expected ask on it.skip"

# 2. describe.only added
begin_test "asks when describe.only is added"
J=$(mk t2 Edit /x/foo.spec.ts 'describe("s", () => {})' 'describe.only("s", () => {})')
asks "$J" && pass || fail "expected ask on describe.only"

# 3. @pytest.mark.skip added
begin_test "asks when @pytest.mark.skip is added"
J=$(mk t3 Edit /x/test_foo.py 'def test_x():\n    assert a == 1' '@pytest.mark.skip\ndef test_x():\n    assert a == 1')
asks "$J" && pass || fail "expected ask on pytest.mark.skip"

# 4. assertion removed
begin_test "asks when an assertion is deleted"
J=$(mk t4 Edit /x/foo_test.py 'assert a == 1\n    assert b == 2' 'assert a == 1')
asks "$J" && pass || fail "expected ask on assertion removal"

# 5. Go t.Skip
begin_test "asks on Go t.Skip in a _test.go file"
J=$(mk t5 Edit /x/foo_test.go 'func TestX(t *testing.T){ require.Equal(t,1,a) }' 'func TestX(t *testing.T){ t.Skip("later"); require.Equal(t,1,a) }')
asks "$J" && pass || fail "expected ask on t.Skip"

# 6. Rust #[ignore]
begin_test "asks on Rust #[ignore]"
J=$(mk t6 Edit /x/foo_test.rs '#[test]\nfn works(){ assert_eq!(a,1); }' '#[test]\n#[ignore]\nfn works(){ assert_eq!(a,1); }')
asks "$J" && pass || fail "expected ask on #[ignore]"

# 7. JUnit @Ignore
begin_test "asks on JUnit @Ignore"
J=$(mk t7 Edit /x/FooTest.java '@Test\nvoid works(){ assertEquals(1,a); }' '@Ignore\n@Test\nvoid works(){ assertEquals(1,a); }')
asks "$J" && pass || fail "expected ask on @Ignore"

# 8. non-test file: silent even when an assertion-like token is removed
begin_test "silent on a non-test source file"
J=$(mk t8 Edit /x/app.js 'expect(a).toBe(1)' 'x')
asks "$J" && fail "should not ask on non-test file" || pass

# 9. adding assertions (no skip, no removal): silent
begin_test "silent when assertions are ADDED"
J=$(mk t9 Edit /x/foo.spec.ts 'expect(a).toBe(1)' 'expect(a).toBe(1)\nexpect(b).toBe(2)')
asks "$J" && fail "should not ask when assertions added" || pass

# 10. MultiEdit with a skip in one edit
begin_test "asks on MultiEdit that adds a skip"
J=$(mk t10 MultiEdit /x/foo.test.js 'it("a",()=>{expect(x).toBe(1)})' 'xit("a",()=>{expect(x).toBe(1)})')
asks "$J" && pass || fail "expected ask on MultiEdit skip"

# 11. Write over existing test file removing assertions
begin_test "asks on Write that removes assertions vs on-disk file"
EXIST="$TMP/existing.test.js"
printf 'it("a",()=>{ expect(x).toBe(1); expect(y).toBe(2); })\n' > "$EXIST"
J=$(mk t11 Write "$EXIST" '' 'it("a",()=>{ expect(x).toBe(1); })')
asks "$J" && pass || fail "expected ask on Write assertion removal"

# 12. Write a brand-new test file (no prior on disk): silent
begin_test "silent on Write of a brand-new test file"
J=$(mk t12 Write "$TMP/brand-new.test.js" '' 'it("a",()=>{})')
asks "$J" && fail "should not ask on new test file authoring" || pass

# 13. kill switch
begin_test "kill switch SUPERCHARGER_TEST_INTEGRITY_GUARD=0 suppresses"
J=$(mk t13 Edit /x/foo.test.js 'it("w",()=>{expect(a).toBe(1)})' 'it.skip("w",()=>{expect(a).toBe(1)})')
OUT=$(SUPERCHARGER_TEST_INTEGRITY_GUARD=0 bash "$HOOK" < "$J" 2>/dev/null)
[ -z "$OUT" ] && pass || fail "kill switch should suppress"

# 14. malformed JSON: fail-open (no output, no crash)
begin_test "fail-open on malformed input"
printf 'not json' > "$TMP/bad.json"
OUT=$(bash "$HOOK" < "$TMP/bad.json" 2>/dev/null); RC=$?
[ -z "$OUT" ] && [ "$RC" -eq 0 ] && pass || fail "should fail-open silently (rc=$RC out=$OUT)"

# --- v4.0.25: the lint-config arm ---------------------------------------------
# Editing the TEST to pass was guarded here; editing the LINTER so the check stops
# complaining was guarded nowhere. test-mask-guard covers the command channel
# (`npm test || true`), this file covered the test file, and the rules the check
# runs under were the missing arm. Gap found in aksheyw/claude-code-guardrail-hooks
# and verified by probe: an Edit turning "error" into "off" in an in-project
# .eslintrc.json passed every PreToolUse hook silently.
#
# Count-deltas, not "this file was touched" — their version denies every edit to an
# existing lint config, and a guard that fires on ordinary work gets switched off.
lint() { # name file old new -> ASK | silent
  local j; j=$(mk "$1" Edit "$2" "$3" "$4")
  [ -n "$(bash "$HOOK" < "$j" 2>/dev/null)" ] && echo ASK || echo silent
}

begin_test "lint: an eslint rule switched to off asks"
[ "$(lint l1 /p/.eslintrc.json '"no-any": "error"' '"no-any": "off"')" = ASK ] && pass || fail "silent"

begin_test "lint: a numeric severity 2 -> 0 asks"
[ "$(lint l2 /p/.eslintrc.json '"a": 2,' '"a": 0,')" = ASK ] && pass || fail "silent"

begin_test "lint: a deleted rule asks (a disable-token scan alone cannot see this)"
[ "$(lint l3 /p/.eslintrc.json '"a": "error", "b": "error"' '"a": "error"')" = ASK ] && pass || fail "silent"

begin_test "lint: tsconfig strict true -> false asks"
[ "$(lint l4 /p/tsconfig.json '"strict": true' '"strict": false')" = ASK ] && pass || fail "silent"

begin_test "lint: a case-swapped .ESLintRC.json is the same file, and asks"
[ "$(lint l5 /p/.ESLintRC.json '"a": "error"' '"a": "off"')" = ASK ] && pass || fail "silent"

# The FP that the first implementation shipped, found by probing before writing
# tests: prettier has no severities, so counting a bare 1 or 2 as a rule read
# "tabWidth": 2 -> 4 as a dropped rule. Numeric severities are an ESLint spelling
# and are only counted for ESLint/Stylelint configs.
begin_test "lint: prettier tabWidth 2 -> 4 is formatting, not enforcement"
[ "$(lint l6 /p/.prettierrc '"tabWidth": 2,' '"tabWidth": 4,')" = silent ] && pass || fail "false positive"

begin_test "lint: adding a rule is silent"
[ "$(lint l7 /p/.eslintrc.json '"a": "error"' '"a": "error", "b": "error"')" = silent ] && pass || fail "fired on a strengthening edit"

begin_test "lint: reformatting is silent"
[ "$(lint l8 /p/.eslintrc.json '"a":"error"' '"a": "error"')" = silent ] && pass || fail "fired on a no-op"

begin_test "lint: a tsconfig target bump is silent"
[ "$(lint l9 /p/tsconfig.json '"target": "es2020"' '"target": "es2022"')" = silent ] && pass || fail "fired on an unrelated key"

begin_test "lint: an ordinary source file is not a lint config"
[ "$(lint l10 /p/src/app.ts '"a": "error"' '"a": "off"')" = silent ] && pass || fail "matched a non-config"

# The gate in front of the python only admitted payloads containing "test"/"spec".
# A .eslintrc.json payload contains neither, so without the gate arm the whole
# thing is unreachable and every test above would still pass ([[two-gate-trap]]).
begin_test "lint: the fast-path gate admits a payload with no test/spec token"
J=$(mk l11 Edit /p/.eslintrc.json '"a": "error"' '"a": "off"')
grep -qiE '"(file_path|old_string|new_string)":[^,]*(test|spec)' "$J" \
  && fail "fixture leaks a test/spec token — it would pass through the OLD gate" \
  || { [ -n "$(bash "$HOOK" < "$J" 2>/dev/null)" ] && pass || fail "gate dropped it"; }

begin_test "lint: SUPERCHARGER_LINT_CONFIG_GUARD=0 disables the arm alone"
J=$(mk l12 Edit /p/.eslintrc.json '"a": "error"' '"a": "off"')
OUT=$(SUPERCHARGER_LINT_CONFIG_GUARD=0 bash "$HOOK" < "$J" 2>/dev/null)
[ -z "$OUT" ] && pass || fail "arm kill switch ignored"

begin_test "lint: and the test arm still works with the lint arm off"
J=$(mk l13 Edit /x/foo.test.js 'it("w",()=>{expect(a).toBe(1)})' 'it.skip("w",()=>{expect(a).toBe(1)})')
OUT=$(SUPERCHARGER_LINT_CONFIG_GUARD=0 bash "$HOOK" < "$J" 2>/dev/null)
[ -n "$OUT" ] && pass || fail "the arm switch disabled the whole hook"

rm -rf "$TMP"
report
