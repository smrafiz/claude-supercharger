#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

HOOK="$REPO_DIR/hooks/env-file-guard.sh"

echo "=== Env File Guard Tests ==="

run_input() {
  local input="$1"
  printf '%s' "$input" | bash "$HOOK" >/dev/null 2>&1
  return $?
}

begin_test "env-guard: blocks 'cat .env'"
run_input '{"tool_name":"Bash","tool_input":{"command":"cat .env"}}'
[ "$?" = "2" ] && pass || fail "cat .env not blocked"

begin_test "env-guard: blocks 'vim .env'"
run_input '{"tool_name":"Bash","tool_input":{"command":"vim .env"}}'
[ "$?" = "2" ] && pass || fail "vim .env not blocked"

begin_test "env-guard: blocks 'grep KEY .env'"
run_input '{"tool_name":"Bash","tool_input":{"command":"grep API_KEY .env"}}'
[ "$?" = "2" ] && pass || fail "grep .env not blocked"

begin_test "env-guard: blocks 'cp .env elsewhere'"
run_input '{"tool_name":"Bash","tool_input":{"command":"cp .env /tmp/backup"}}'
[ "$?" = "2" ] && pass || fail "cp .env not blocked"

begin_test "env-guard: allows 'cat .env.example'"
run_input '{"tool_name":"Bash","tool_input":{"command":"cat .env.example"}}'
[ "$?" = "0" ] && pass || fail ".env.example incorrectly blocked"

begin_test "env-guard: allows 'cat .env.template'"
run_input '{"tool_name":"Bash","tool_input":{"command":"cat .env.template"}}'
[ "$?" = "0" ] && pass || fail ".env.template incorrectly blocked"

begin_test "env-guard: allows git commit mentioning .env"
run_input '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"update .env handling\""}}'
[ "$?" = "0" ] && pass || fail "git commit incorrectly blocked"

begin_test "env-guard: allows gh pr create mentioning .env"
run_input '{"tool_name":"Bash","tool_input":{"command":"gh pr create --body \"changed .env\""}}'
[ "$?" = "0" ] && pass || fail "gh pr create incorrectly blocked"

begin_test "env-guard: allows unrelated commands"
run_input '{"tool_name":"Bash","tool_input":{"command":"ls -la"}}'
[ "$?" = "0" ] && pass || fail "ls incorrectly blocked"

begin_test "env-guard: blocks Read of .env"
run_input '{"tool_name":"Read","tool_input":{"file_path":"/proj/.env"}}'
[ "$?" = "2" ] && pass || fail "Read .env not blocked"

begin_test "env-guard: blocks Read of .env.local"
run_input '{"tool_name":"Read","tool_input":{"file_path":"/proj/.env.local"}}'
[ "$?" = "2" ] && pass || fail "Read .env.local not blocked"

begin_test "env-guard: allows Read of .env.example"
run_input '{"tool_name":"Read","tool_input":{"file_path":"/proj/.env.example"}}'
[ "$?" = "0" ] && pass || fail ".env.example Read incorrectly blocked"

begin_test "env-guard: allows Read of regular file"
run_input '{"tool_name":"Read","tool_input":{"file_path":"/proj/src/main.py"}}'
[ "$?" = "0" ] && pass || fail "regular file Read incorrectly blocked"

begin_test "env-guard: blocks redirect to .env (write)"
run_input '{"tool_name":"Bash","tool_input":{"command":"echo SECRET=foo > .env"}}'
[ "$?" = "2" ] && pass || fail "redirect to .env not blocked"

report
