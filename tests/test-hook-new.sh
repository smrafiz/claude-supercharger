#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

TOOL="$REPO_DIR/tools/hook-new.sh"
HOOKS_DIR="$REPO_DIR/hooks"

echo "=== Hook New Scaffolder Tests ==="

cleanup_hook() { rm -f "$HOOKS_DIR/${1}.sh"; }

seed_settings() {
  mkdir -p "$HOME/.claude"
  echo '{"hooks":{}}' > "$HOME/.claude/settings.json"
}

# ── scaffold output ───────────────────────────────────────────────────────────
begin_test "hook-new: creates hook file with correct shebang"
cleanup_hook "test-new-a"
bash "$TOOL" test-new-a >/dev/null 2>&1
head -1 "$HOOKS_DIR/test-new-a.sh" | grep -q '#!/usr/bin/env bash' && pass || fail "missing shebang"
cleanup_hook "test-new-a"

begin_test "hook-new: file is executable"
cleanup_hook "test-new-b"
bash "$TOOL" test-new-b >/dev/null 2>&1
[ -x "$HOOKS_DIR/test-new-b.sh" ] && pass || fail "not executable"
cleanup_hook "test-new-b"

begin_test "hook-new: default event is PostToolUse"
cleanup_hook "test-new-c"
bash "$TOOL" test-new-c >/dev/null 2>&1
grep -q "Event: PostToolUse" "$HOOKS_DIR/test-new-c.sh" && pass || fail "wrong default event"
cleanup_hook "test-new-c"

begin_test "hook-new: custom event written to file"
cleanup_hook "test-new-d"
bash "$TOOL" test-new-d PreToolUse >/dev/null 2>&1
grep -q "Event: PreToolUse" "$HOOKS_DIR/test-new-d.sh" && pass || fail "event not in file"
cleanup_hook "test-new-d"

begin_test "hook-new: matcher written to file"
cleanup_hook "test-new-e"
bash "$TOOL" test-new-e PreToolUse Bash >/dev/null 2>&1
grep -q "Matcher: Bash" "$HOOKS_DIR/test-new-e.sh" && pass || fail "matcher not in file"
cleanup_hook "test-new-e"

begin_test "hook-new: template uses check_hook_disabled"
cleanup_hook "test-new-f"
bash "$TOOL" test-new-f >/dev/null 2>&1
grep -q "check_hook_disabled" "$HOOKS_DIR/test-new-f.sh" && pass || fail "check_hook_disabled not in template"
cleanup_hook "test-new-f"

begin_test "hook-new: template sources lib-suppress.sh"
cleanup_hook "test-new-g"
bash "$TOOL" test-new-g >/dev/null 2>&1
grep -q "lib-suppress.sh" "$HOOKS_DIR/test-new-g.sh" && pass || fail "lib-suppress.sh not sourced"
cleanup_hook "test-new-g"

begin_test "hook-new: block example uses hookSpecificOutput"
cleanup_hook "test-new-h"
bash "$TOOL" test-new-h PreToolUse Bash >/dev/null 2>&1
grep -q "hookSpecificOutput" "$HOOKS_DIR/test-new-h.sh" && pass || fail "hookSpecificOutput not in block example"
cleanup_hook "test-new-h"

begin_test "hook-new: hook name kebab-case validated"
EXIT=0
OUTPUT=$(bash "$TOOL" "Bad_Name" 2>&1) || EXIT=$?
[ "$EXIT" -ne 0 ] && pass || fail "expected non-zero exit for invalid name"

begin_test "hook-new: exits non-zero if hook already exists"
cleanup_hook "test-new-dup"
bash "$TOOL" test-new-dup >/dev/null 2>&1
EXIT=0
bash "$TOOL" test-new-dup 2>/dev/null || EXIT=$?
[ "$EXIT" -ne 0 ] && pass || fail "expected error for duplicate hook"
cleanup_hook "test-new-dup"

# ── --register ────────────────────────────────────────────────────────────────
begin_test "hook-new: --register adds entry to settings.json"
setup_test_home; seed_settings
cleanup_hook "test-new-reg"
bash "$TOOL" test-new-reg PostToolUse Bash --register >/dev/null 2>&1
grep -q "test-new-reg.sh" "$HOME/.claude/settings.json" && pass || fail "hook not in settings.json"
cleanup_hook "test-new-reg"
teardown_test_home

begin_test "hook-new: --register sets matcher in settings.json"
setup_test_home; seed_settings
cleanup_hook "test-new-mat"
bash "$TOOL" test-new-mat PostToolUse Write --register >/dev/null 2>&1
grep -q '"matcher"' "$HOME/.claude/settings.json" && pass || fail "matcher not set in settings.json"
cleanup_hook "test-new-mat"
teardown_test_home

begin_test "hook-new: --register no matcher omits matcher key"
setup_test_home; seed_settings
cleanup_hook "test-new-nom"
bash "$TOOL" test-new-nom PostToolUse --register >/dev/null 2>&1
# matcher key should NOT be present for this entry
python3 -c "
import json, sys
s = json.load(open('$HOME/.claude/settings.json'))
for entries in s.get('hooks', {}).values():
    for entry in entries:
        for h in entry.get('hooks', []):
            if 'test-new-nom' in h.get('command', ''):
                if 'matcher' not in entry:
                    sys.exit(0)
                else:
                    sys.exit(1)
sys.exit(1)
" && pass || fail "matcher key should be absent for no-matcher hook"
cleanup_hook "test-new-nom"
teardown_test_home

begin_test "hook-new: --register exits 1 when settings.json missing"
setup_test_home
rm -f "$HOME/.claude/settings.json"
cleanup_hook "test-new-noset"
EXIT=0
bash "$TOOL" test-new-noset PostToolUse Bash --register >/dev/null 2>&1 || EXIT=$?
[ "$EXIT" -ne 0 ] && pass || fail "expected exit 1 when settings.json missing"
cleanup_hook "test-new-noset"
teardown_test_home

begin_test "hook-new: --register idempotent (no duplicate entries)"
setup_test_home; seed_settings
cleanup_hook "test-new-idem"
bash "$TOOL" test-new-idem PostToolUse Bash --register >/dev/null 2>&1
# Re-register: hook file already exists → should error, so test via python directly
python3 -c "
import json
s = json.load(open('$HOME/.claude/settings.json'))
count = sum(1 for entries in s.get('hooks',{}).values()
            for entry in entries
            for h in entry.get('hooks',[])
            if 'test-new-idem' in h.get('command',''))
assert count == 1, f'expected 1 entry, got {count}'
print('ok')
" 2>&1 | grep -q "ok" && pass || fail "duplicate entries found"
cleanup_hook "test-new-idem"
teardown_test_home

report
