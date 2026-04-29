#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

HOOK="$REPO_DIR/hooks/comment-replacement-check.sh"

echo "=== Comment Replacement Check Tests ==="

run_input() {
  local input="$1"
  printf '%s' "$input" | bash "$HOOK" 2>/dev/null
}

begin_test "comment-replacement: flags code → comments (Edit)"
OUT=$(run_input '{"tool_name":"Edit","tool_input":{"file_path":"/tmp/x.js","old_string":"const x = 5;\nconsole.log(x);","new_string":"// const x = 5;\n// console.log(x);"}}')
echo "$OUT" | grep -q "systemMessage" && pass || fail "should flag code-to-comment"

begin_test "comment-replacement: silent on real code change"
OUT=$(run_input '{"tool_name":"Edit","tool_input":{"file_path":"/tmp/x.js","old_string":"const x = 5;","new_string":"const x = 10;"}}')
[ -z "$OUT" ] && pass || fail "should not flag legit code change"

begin_test "comment-replacement: silent on comment-to-comment"
OUT=$(run_input '{"tool_name":"Edit","tool_input":{"file_path":"/tmp/x.js","old_string":"// old comment","new_string":"// new comment"}}')
[ -z "$OUT" ] && pass || fail "should not flag comment-only edits"

begin_test "comment-replacement: skips markdown files"
OUT=$(run_input '{"tool_name":"Edit","tool_input":{"file_path":"/tmp/readme.md","old_string":"old","new_string":"// new"}}')
[ -z "$OUT" ] && pass || fail "should skip .md files"

begin_test "comment-replacement: skips .txt files"
OUT=$(run_input '{"tool_name":"Edit","tool_input":{"file_path":"/tmp/notes.txt","old_string":"old","new_string":"// new"}}')
[ -z "$OUT" ] && pass || fail "should skip .txt files"

begin_test "comment-replacement: flags MultiEdit code-to-comments"
OUT=$(run_input '{"tool_name":"MultiEdit","tool_input":{"file_path":"/tmp/x.py","edits":[{"old_string":"def foo():\n    return 42","new_string":"# def foo():\n#     return 42"}]}}')
echo "$OUT" | grep -q "systemMessage" && pass || fail "should flag MultiEdit code-to-comment"

begin_test "comment-replacement: silent on Read tool"
OUT=$(run_input '{"tool_name":"Read","tool_input":{"file_path":"/tmp/x.py"}}')
[ -z "$OUT" ] && pass || fail "should ignore non-Edit tools"

begin_test "comment-replacement: silent on clean delete (empty new_string)"
OUT=$(run_input '{"tool_name":"Edit","tool_input":{"file_path":"/tmp/x.py","old_string":"def foo():\n    return 42","new_string":""}}')
[ -z "$OUT" ] && pass || fail "should not flag clean deletion"

begin_test "comment-replacement: flags Python comments"
OUT=$(run_input '{"tool_name":"Edit","tool_input":{"file_path":"/tmp/x.py","old_string":"def foo():\n    return 42","new_string":"# def foo():\n#     return 42"}}')
echo "$OUT" | grep -q "systemMessage" && pass || fail "should flag # comments"

begin_test "comment-replacement: flags HTML comments"
OUT=$(run_input '{"tool_name":"Edit","tool_input":{"file_path":"/tmp/x.html","old_string":"<div>foo</div>\n<span>bar</span>","new_string":"<!-- <div>foo</div> -->\n<!-- <span>bar</span> -->"}}')
echo "$OUT" | grep -q "systemMessage" && pass || fail "should flag HTML comments"

report
