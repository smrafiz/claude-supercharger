#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

HOOK="$REPO_DIR/hooks/file-watcher.sh"

run_file_watcher() {
  local file_path="$1"
  echo "{\"file_path\":\"$file_path\"}" | bash "$HOOK" 2>/dev/null
}

echo "=== File Watcher Hook Tests ==="

begin_test "file-watcher: .env change emits env context"
output=$(run_file_watcher "/project/.env")
if echo "$output" | grep -q "Environment variables"; then pass; else fail "expected env message"; fi

begin_test "file-watcher: .envrc change emits env context"
output=$(run_file_watcher "/project/.envrc")
if echo "$output" | grep -q "Environment variables"; then pass; else fail "expected env message"; fi

begin_test "file-watcher: package.json change emits install context"
output=$(run_file_watcher "/project/package.json")
if echo "$output" | grep -q "install"; then pass; else fail "expected install message"; fi

begin_test "file-watcher: settings.json change emits CVE warning"
output=$(run_file_watcher "/project/.claude/settings.json")
if echo "$output" | grep -q "CVE-2025-59536"; then pass; else fail "expected CVE warning"; fi

begin_test "file-watcher: unknown file emits generic context"
output=$(run_file_watcher "/project/somefile.txt")
if echo "$output" | grep -q "modified externally"; then pass; else fail "expected generic message"; fi

begin_test "file-watcher: empty file_path exits cleanly"
exit_code=$(echo '{}' | bash "$HOOK" >/dev/null 2>&1; echo $?)
assert_exit_code 0 "$exit_code" && pass

begin_test "file-watcher: output is valid JSON"
output=$(run_file_watcher "/project/package.json")
if echo "$output" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null; then pass; else fail "output not valid JSON"; fi

begin_test "file-watcher: output contains hookEventName FileChanged"
output=$(run_file_watcher "/project/package.json")
if echo "$output" | python3 -c "import sys,json; d=json.load(sys.stdin); assert d['hookSpecificOutput']['hookEventName']=='FileChanged'" 2>/dev/null; then pass; else fail "missing hookEventName"; fi

report
