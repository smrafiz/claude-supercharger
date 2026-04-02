#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

# --- Test: non-interactive fresh install ---
begin_test "install: non-interactive fresh install"
setup_test_home

bash "$REPO_DIR/install.sh" --mode standard --roles developer --config deploy --settings deploy --economy lean >/dev/null 2>&1

assert_file_exists "$HOME/.claude/CLAUDE.md" &&
assert_file_exists "$HOME/.claude/rules/supercharger.md" &&
assert_file_exists "$HOME/.claude/rules/guardrails.md" &&
assert_file_exists "$HOME/.claude/rules/developer.md" &&
assert_file_exists "$HOME/.claude/rules/anti-patterns.yml" &&
assert_file_not_exists "$HOME/.claude/rules/writer.md" &&
assert_file_exists "$HOME/.claude/supercharger/roles/writer.md" &&
assert_file_exists "$HOME/.claude/settings.json" &&
assert_file_exists "$HOME/.claude/rules/economy.md" &&
pass
teardown_test_home

# --- Test: non-interactive merge preserves existing content ---
begin_test "install: non-interactive merge preserves existing content"
setup_test_home
mkdir -p "$HOME/.claude"
echo "# My Existing Config" > "$HOME/.claude/CLAUDE.md"
echo "keep this" >> "$HOME/.claude/CLAUDE.md"

bash "$REPO_DIR/install.sh" --mode safe --roles writer --config merge --settings deploy --economy standard >/dev/null 2>&1

assert_file_contains "$HOME/.claude/CLAUDE.md" "My Existing Config" &&
assert_file_contains "$HOME/.claude/CLAUDE.md" "keep this" &&
assert_file_contains "$HOME/.claude/CLAUDE.md" "Claude Supercharger" &&
assert_file_contains "$HOME/.claude/CLAUDE.md" "Verification Gate" &&
pass
teardown_test_home

# --- Test: non-interactive skip leaves CLAUDE.md untouched ---
begin_test "install: non-interactive skip leaves CLAUDE.md untouched"
setup_test_home
mkdir -p "$HOME/.claude"
echo "# Untouched" > "$HOME/.claude/CLAUDE.md"

bash "$REPO_DIR/install.sh" --mode safe --roles developer --config skip --settings skip --economy lean >/dev/null 2>&1

assert_file_contains "$HOME/.claude/CLAUDE.md" "Untouched" &&
assert_file_not_contains "$HOME/.claude/CLAUDE.md" "Supercharger" &&
assert_file_exists "$HOME/.claude/rules/supercharger.md" &&
pass
teardown_test_home

# --- Test: idempotent install ---
begin_test "install: idempotent — no duplicate hooks after double install"
setup_test_home

bash "$REPO_DIR/install.sh" --mode standard --roles developer --config deploy --settings deploy --economy lean >/dev/null 2>&1
bash "$REPO_DIR/install.sh" --mode standard --roles developer --config deploy --settings deploy --economy lean >/dev/null 2>&1

HOOK_COUNT=$(SETTINGS="$HOME/.claude/settings.json" python3 -c "
import json, os
with open(os.environ['SETTINGS']) as f:
    s = json.load(f)
hooks = s.get('hooks', {})
count = sum(1 for event in hooks.values() for entry in event
            for h in entry.get('hooks', [])
            if '#supercharger' in h.get('command',''))
print(count)
")
# Standard mode + developer = safety + notify + git-safety + enforce-pkg-manager + audit-trail + project-config + quality-gate = 7
if [ "$HOOK_COUNT" -eq 7 ]; then
  pass
else
  fail "expected 6 hooks, got $HOOK_COUNT"
fi
teardown_test_home

# --- Test: statusline is registered in settings.json ---
begin_test "install: statusline registered in settings.json"
setup_test_home

bash "$REPO_DIR/install.sh" --mode standard --roles developer --config deploy --settings deploy --economy lean >/dev/null 2>&1

HAS_STATUSLINE=$(SETTINGS="$HOME/.claude/settings.json" python3 -c "
import json, os
with open(os.environ['SETTINGS']) as f:
    s = json.load(f)
sl = s.get('statusLine', {}).get('command', '')
print('yes' if '#supercharger' in sl else 'no')
")
[ "$HAS_STATUSLINE" = "yes" ] && pass || fail "statusLine not found in settings.json"
teardown_test_home

# --- Test: agents deployed on install ---
begin_test "install: agents deployed to ~/.claude/agents/"
setup_test_home

bash "$REPO_DIR/install.sh" --mode standard --roles developer --config deploy --settings deploy --economy lean >/dev/null 2>&1

assert_dir_exists "$HOME/.claude/agents" &&
assert_file_exists "$HOME/.claude/agents/code-helper.md" &&
assert_file_exists "$HOME/.claude/agents/debugger.md" &&
assert_file_exists "$HOME/.claude/agents/writer.md" &&
assert_file_exists "$HOME/.claude/agents/reviewer.md" &&
assert_file_exists "$HOME/.claude/agents/researcher.md" &&
assert_file_exists "$HOME/.claude/agents/planner.md" &&
assert_file_exists "$HOME/.claude/agents/data-analyst.md" &&
assert_file_exists "$HOME/.claude/agents/general.md" &&
pass
teardown_test_home

# --- Test: help flag ---
begin_test "install: --help prints usage and exits"
OUTPUT=$(bash "$REPO_DIR/install.sh" --help 2>&1) || true
echo "$OUTPUT" | grep -qi "usage" && pass || fail "no usage text"

report
