#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

HOOK="$REPO_DIR/hooks/shell-wrapper-guard.sh"

echo "=== Shell Wrapper Guard Tests ==="

run_with_command() {
  local cmd="$1"
  cat > /tmp/swg-test.json <<EOF
{"tool_input":{"command":$cmd}}
EOF
  bash "$HOOK" < /tmp/swg-test.json >/dev/null 2>&1
  local rc=$?
  rm -f /tmp/swg-test.json
  return $rc
}

begin_test "shell-wrapper: blocks python -c with rm -rf /"
run_with_command '"python3 -c '"'"'import os; os.system(\"rm -rf /\")'"'"'"'
[ "$?" = "2" ] && pass || fail "python rm / not blocked"

begin_test "shell-wrapper: blocks node -e with rm -rf /"
run_with_command '"node -e '"'"'require(\"child_process\").execSync(\"rm -rf /\")'"'"'"'
[ "$?" = "2" ] && pass || fail "node rm / not blocked"

begin_test "shell-wrapper: blocks perl -e with rm -rf /"
run_with_command '"perl -e '"'"'system(\"rm -rf /\")'"'"'"'
[ "$?" = "2" ] && pass || fail "perl rm / not blocked"

begin_test "shell-wrapper: blocks ruby -e with rm -rf /"
run_with_command '"ruby -e '"'"'system(\"rm -rf /\")'"'"'"'
[ "$?" = "2" ] && pass || fail "ruby rm / not blocked"

begin_test "shell-wrapper: blocks python -c with rm -rf ~"
run_with_command '"python3 -c '"'"'import os; os.system(\"rm -rf ~\")'"'"'"'
[ "$?" = "2" ] && pass || fail "python rm ~ not blocked"

begin_test "shell-wrapper: blocks node -e with git reset --hard"
run_with_command '"node -e '"'"'require(\"child_process\").execSync(\"git reset --hard\")'"'"'"'
[ "$?" = "2" ] && pass || fail "node git reset not blocked"

begin_test "shell-wrapper: blocks python -c with rm -rf /*"
run_with_command '"python3 -c '"'"'import os; os.system(\"rm -rf /*\")'"'"'"'
[ "$?" = "2" ] && pass || fail "python rm /* not blocked"

begin_test "shell-wrapper: allows ruby rm /tmp (safe path)"
run_with_command '"ruby -e '"'"'system(\"rm -rf /tmp\")'"'"'"'
[ "$?" = "0" ] && pass || fail "false positive on /tmp"

begin_test "shell-wrapper: allows python rm ./dist (safe path)"
run_with_command '"python3 -c '"'"'import os; os.system(\"rm -rf ./dist\")'"'"'"'
[ "$?" = "0" ] && pass || fail "false positive on ./dist"

begin_test "shell-wrapper: allows plain echo"
run_with_command '"echo hi"'
[ "$?" = "0" ] && pass || fail "false positive on echo"

begin_test "shell-wrapper: allows node legit script"
run_with_command '"node -e '"'"'console.log(\"hi\")'"'"'"'
[ "$?" = "0" ] && pass || fail "false positive on console.log"

begin_test "shell-wrapper: allows direct rm (covered by safety.sh)"
run_with_command '"rm -rf /"'
[ "$?" = "0" ] && pass || fail "should not block direct rm (safety.sh handles it)"

report
