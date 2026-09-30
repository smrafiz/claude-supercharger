#!/usr/bin/env bash
# tools/input-budget.sh — measures what loads at every session start.
#
# Built against an isolated HOME and project so the numbers are exact: a global
# CLAUDE.md with an @import, a Supercharger rules file, a project CLAUDE.md, a
# path-scoped project rule (must NOT be counted) and a memory index.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
echo "=== input-budget ==="
TOOL="$REPO_DIR/tools/input-budget.sh"

T=$(mktemp -d)
H="$T/home"; P="$T/proj"
mkdir -p "$H/.claude/rules" "$P/.claude/rules"
P_REAL=$(cd "$P" && pwd -P)
ENC="-$(printf '%s' "$P_REAL" | sed 's|/|-|g; s|^-||')"
mkdir -p "$H/.claude/projects/$ENC/memory"
printf 'user notes\n@extra.md\n# --- Claude Supercharger v9 ---\nblock\n' > "$H/.claude/CLAUDE.md"
printf 'imported\n' > "$H/.claude/extra.md"
printf '%0400d' 0 > "$H/.claude/rules/economy.md"
printf '%0100d' 0 > "$P/CLAUDE.md"
printf -- '---\npaths: src/**\n---\nonly for src\n' > "$P/.claude/rules/scoped.md"
printf '%0200d' 0 > "$H/.claude/projects/$ENC/memory/MEMORY.md"

run() { HOME="$H" SUPERCHARGER_INPUT_BUDGET_KB="${BUDGET:-32}" bash "$TOOL" --dir "$P" "$@" 2>&1; }

OUT=$(run)
begin_test "input-budget: follows @imports and counts every always-loaded file"
G=$(wc -c < "$H/.claude/CLAUDE.md"); X=$(wc -c < "$H/.claude/extra.md")
TOTAL=$(( G + X + 400 + 100 + 200 ))
printf '%s' "$OUT" | grep -q 'extra.md' && printf '%s' "$OUT" | grep -q "~$(( TOTAL / 4 )) tok" \
  && pass || fail "expected total $TOTAL B: $OUT"

begin_test "input-budget: a path-scoped rule is listed but not counted"
printf '%s' "$OUT" | grep -q 'path-scoped' && printf '%s' "$OUT" | grep -q 'scoped.md' \
  && pass || fail "scoped rule missing or counted: $OUT"

begin_test "input-budget: only the managed block of CLAUDE.md counts as Supercharger"
SC=$(( $(printf '# --- Claude Supercharger v9 ---\nblock\n' | wc -c) + 400 ))
printf '%s' "$OUT" | grep -q "Supercharger-managed .*(~$(( SC / 4 )) tok)" \
  && pass || fail "expected Supercharger $SC B: $OUT"

begin_test "input-budget: --line reports within budget, and OVER when exceeded"
L1=$(run --line); L2=$(BUDGET=0.5 run --line)
case "$L1$L2" in *"within 32 KB"*"OVER budget 0.5 KB"*) pass ;; *) fail "L1=$L1 L2=$L2" ;; esac

begin_test "input-budget: exits 0 even over budget (report-only)"
BUDGET=0.1 run --line >/dev/null; [ $? -eq 0 ] && pass || fail "non-zero exit over budget"

rm -rf "$T"
report
