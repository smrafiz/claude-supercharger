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

rm -rf "$TMP"
report
