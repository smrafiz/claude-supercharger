#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

HOOK="$REPO_DIR/hooks/lazy-refactor-check.sh"

echo "=== Lazy Refactor Check Tests ==="

run_input() {
  printf '%s' "$1" | bash "$HOOK" 2>/dev/null
}

begin_test "lazy-refactor: flags TS function param rename to underscore"
OUT=$(run_input '{"tool_name":"Edit","tool_input":{"file_path":"/x.ts","old_string":"function foo(name) {}","new_string":"function foo(_name) {}"}}')
echo "$OUT" | grep -q "systemMessage" && pass || fail "should flag _name rename"

begin_test "lazy-refactor: flags JS arrow function rename"
OUT=$(run_input '{"tool_name":"Edit","tool_input":{"file_path":"/x.js","old_string":"const f = (x) => 1;","new_string":"const f = (_x) => 1;"}}')
echo "$OUT" | grep -q "systemMessage" && pass || fail "should flag arrow rename"

begin_test "lazy-refactor: flags Python def rename"
OUT=$(run_input '{"tool_name":"Edit","tool_input":{"file_path":"/x.py","old_string":"def foo(bar):\n    pass","new_string":"def foo(_bar):\n    pass"}}')
echo "$OUT" | grep -q "systemMessage" && pass || fail "should flag Python rename"

begin_test "lazy-refactor: silent on real param replacement"
OUT=$(run_input '{"tool_name":"Edit","tool_input":{"file_path":"/x.ts","old_string":"function foo(name) { return name; }","new_string":"function bar(label) { return label; }"}}')
[ -z "$OUT" ] && pass || fail "should not flag legit change"

begin_test "lazy-refactor: silent on param removal"
OUT=$(run_input '{"tool_name":"Edit","tool_input":{"file_path":"/x.ts","old_string":"function foo(name, age) {}","new_string":"function foo(name) {}"}}')
[ -z "$OUT" ] && pass || fail "should not flag clean removal"

begin_test "lazy-refactor: skips markdown"
OUT=$(run_input '{"tool_name":"Edit","tool_input":{"file_path":"/r.md","old_string":"function foo(name)","new_string":"function foo(_name)"}}')
[ -z "$OUT" ] && pass || fail "should skip .md"

begin_test "lazy-refactor: silent when no params"
OUT=$(run_input '{"tool_name":"Edit","tool_input":{"file_path":"/x.ts","old_string":"const x = 1;","new_string":"const x = 2;"}}')
[ -z "$OUT" ] && pass || fail "should skip non-param edits"

begin_test "lazy-refactor: flags MultiEdit param rename"
OUT=$(run_input '{"tool_name":"MultiEdit","tool_input":{"file_path":"/x.ts","edits":[{"old_string":"function foo(x)","new_string":"function foo(_x)"}]}}')
echo "$OUT" | grep -q "systemMessage" && pass || fail "should flag MultiEdit rename"

begin_test "lazy-refactor: silent on Read tool"
OUT=$(run_input '{"tool_name":"Read","tool_input":{"file_path":"/x.ts"}}')
[ -z "$OUT" ] && pass || fail "should ignore Read"

report
