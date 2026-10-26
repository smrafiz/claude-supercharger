#!/usr/bin/env bash
# 4.4: <private>…</private> never reaches Supercharger's memory, and the session-start
# handoff is an outline (every section, plus the path) instead of a byte cut.
# Both ideas from the thedotmack/claude-mem audit, 2026-10-26.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

echo "=== private tag + handoff outline ==="

begin_test "private: spans are removed, an unclosed tag drops the rest"
OUT=$(bash -c '. "$1/hooks/lib-prompt-source.sh"
  A="keep <private>s1</private> mid <private>s2</private> end"; sc_strip_private A
  B="keep <private>never closed"; sc_strip_private B
  printf "%s|%s" "$A" "$B"' _ "$REPO_DIR")
case "$OUT" in *s1*|*s2*|*closed*) fail "private text kept: $OUT" ;; "keep  mid  end|keep ") pass ;; *) fail "unexpected: $OUT" ;; esac

begin_test "private: a correction inside <private> is not logged"
ST=$(mktemp -d); P=$(mktemp -d)
printf '%s' "{\"prompt\":\"<private>don't use the staging key abc123</private>\",\"cwd\":\"$P\",\"session_id\":\"pv\"}" \
  | SUPERCHARGER_STATE="$ST" bash "$REPO_DIR/hooks/learn-from-prompts.sh" >/dev/null 2>&1
if grep -rq 'abc123' "$ST" 2>/dev/null; then fail "private correction was logged"; else pass; fi

begin_test "private: the same correction without the tag IS logged (control)"
printf '%s' "{\"prompt\":\"don't use the staging key abc123\",\"cwd\":\"$P\",\"session_id\":\"pv\"}" \
  | SUPERCHARGER_STATE="$ST" bash "$REPO_DIR/hooks/learn-from-prompts.sh" >/dev/null 2>&1
grep -rq 'abc123' "$ST" 2>/dev/null && pass || fail "control correction was not logged; the test proves nothing"
rm -rf "$ST" "$P"

begin_test "handoff outline: every section heading and the path survive the 2500-byte cap"
H=$(mktemp -d); F="$H/handoff.md"
{ echo "## Handoff — demo — 2026-10-26"
  for s in Done "In Flight" Decisions "What Failed" Blockers "Files Touched" "Resume With" "Start With" Measurements; do
    echo "### $s"; for i in $(seq 1 12); do echo "- $s detail line $i with enough words to fill a realistic brief entry here"; done
  done; } > "$F"
OUT=$(bash -c '. "$1/hooks/lib-handoff.sh"; handoff_index "$2" | head -c 2500' _ "$REPO_DIR" "$F")
HEADS=$(printf '%s\n' "$OUT" | grep -c '^### ')
{ [ "$HEADS" = 9 ] && printf '%s' "$OUT" | grep -q "Outline of $F" && printf '%s' "$OUT" | grep -q '(+10 more lines)'; } \
  && pass || fail "headings=$HEADS (want 9), path or counts missing: $(printf '%s' "$OUT" | head -3)"
CUT=$(head -c 2500 "$F" | grep -c '^### ')
begin_test "handoff outline: the old byte cut kept fewer sections (control)"
[ "$CUT" -lt 9 ] && pass || fail "the fixture is too small to show the difference ($CUT sections)"
rm -rf "$H"

report
