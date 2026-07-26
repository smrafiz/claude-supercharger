#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

HOOK="$REPO_DIR/hooks/commit-guard.sh"

echo "=== commit-guard code-scan (Check 4) Tests ==="
export SUPERCHARGER_NO_DEDUP=1

# Absolute HOOK path so $HOOKS_DIR survives the subshell `cd $PROJECT_DIR`.
_run() { # <repo-cwd> <command> [enabled=1]
  local cwd="$1" cmd="$2" en="${3:-1}"
  printf '{"tool_name":"Bash","tool_input":{"command":"%s"},"cwd":"%s","session_id":"cs1"}' "$cmd" "$cwd" \
    | SUPERCHARGER_STATE="$(mktemp -d)" SUPERCHARGER_COMMIT_CODE_SCAN="$en" bash "$HOOK" 2>/dev/null
}
_newrepo() { local d; d=$(mktemp -d); ( cd "$d" && git init -q && git config user.email t@t && git config user.name t ); echo "$d"; }
_stage() { printf '%s' "$2" > "$1/f"; ( cd "$1" && git add f ); }

begin_test "code-scan: staged os.popen asks on commit"
D=$(_newrepo); _stage "$D" "import os
out = os.popen(command_str).read()"
OUT=$(_run "$D" "git commit -m feat-x")
echo "$OUT" | grep -q 'permissionDecision.*ask' && echo "$OUT" | grep -qi 'os.popen\|insecure' && pass || fail "expected ASK, got: $OUT"
rm -rf "$D"

begin_test "code-scan: staged Node execSync asks on commit"
D=$(_newrepo); _stage "$D" "const cp = require('child_process');
cp.execSync(userInput);"
OUT=$(_run "$D" "git commit -m feat-y")
echo "$OUT" | grep -q 'permissionDecision.*ask' && pass || fail "expected ASK, got: $OUT"
rm -rf "$D"

begin_test "code-scan: staged yaml.load asks on commit"
D=$(_newrepo); _stage "$D" "import yaml
cfg = yaml.load(open(p))"
OUT=$(_run "$D" "git commit -m feat-z")
echo "$OUT" | grep -q 'permissionDecision.*ask' && pass || fail "expected ASK, got: $OUT"
rm -rf "$D"

begin_test "code-scan: clean staged code does not ask"
D=$(_newrepo); _stage "$D" "def add(a, b):
    return a + b"
OUT=$(_run "$D" "git commit -m feat-clean")
[ -z "$OUT" ] && pass || fail "expected SILENT on clean code, got: $OUT"
rm -rf "$D"

begin_test "code-scan: kill switch disables the scan"
D=$(_newrepo); _stage "$D" "import os
out = os.popen(command_str).read()"
OUT=$(_run "$D" "git commit -m feat-x" 0)
[ -z "$OUT" ] && pass || fail "expected SILENT when disabled, got: $OUT"
rm -rf "$D"

begin_test "code-scan: non-commit command is ignored"
D=$(_newrepo); _stage "$D" "import os
out = os.popen(command_str).read()"
OUT=$(_run "$D" "git status")
[ -z "$OUT" ] && pass || fail "expected SILENT on non-commit command, got: $OUT"
rm -rf "$D"

report
