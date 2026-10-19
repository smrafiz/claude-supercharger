#!/usr/bin/env bash
# tools/writing-mode.sh turns opt-in writing modes (configs/rules/*.md) on and off
# by placing a copy in ~/.claude/rules, which Claude Code loads at session start.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/home/.claude/supercharger/rules/modes"
cp "$REPO_DIR/configs/rules/"*.md "$T/home/.claude/supercharger/rules/modes/"
wm() { HOME="$T/home" SUPERCHARGER_HOME="$T/home/.claude/supercharger" bash "$REPO_DIR/tools/writing-mode.sh" "$@" 2>&1; }
RULE="$T/home/.claude/rules/sc-mode-ste.md"

echo "=== Writing Mode Tests ==="

begin_test "ste starts off"
wm ste status | grep -q "off" && [ ! -e "$RULE" ] && pass || fail "$(wm ste status)"

begin_test "on places the rule where Claude Code loads it, byte for byte"
wm ste on >/dev/null
cmp -s "$RULE" "$REPO_DIR/configs/rules/ste.md" && pass || fail "rule file missing or different"

begin_test "status and list report it on"
{ wm ste status | grep -q ": on" && wm list | grep -qE "ste +on"; } && pass || fail "$(wm list)"

begin_test "off removes it"
wm ste off >/dev/null; [ ! -e "$RULE" ] && pass || fail "rule file still present"

begin_test "GAP CHECK: an unknown or path-shaped mode name is refused"
wm '../../evil' on >/dev/null; RC=$?
[ "$RC" -eq 2 ] && [ -z "$(ls "$T/home/.claude/rules" 2>/dev/null)" ] && pass || fail "rc=$RC"

begin_test "the STE rule keeps code exact and states the 80% scope"
grep -q "never" "$REPO_DIR/configs/rules/ste.md" && grep -qi "80%" "$REPO_DIR/configs/rules/ste.md" && pass || fail "rule text"

begin_test "sc-handoff documents --html and that it stacks with --deep"
H="$REPO_DIR/configs/commands/sc-handoff.md"
{ grep -q -- '--deep --html' "$H" && grep -q 'Step 6' "$H" && grep -q 'runs LAST, after Step 5' "$H"; } && pass || fail "handoff flags"

report
