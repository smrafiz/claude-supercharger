#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

TOOL="$REPO_DIR/tools/memory-prune.sh"
echo "=== Memory Prune Tests ==="

setup_mem() {
  MEM=$(mktemp -d)/memory; mkdir -p "$MEM"
  printf -- '---\nname: fb\nmetadata:\n  type: feedback\n---\nrule\n'                            > "$MEM/fb.md"
  printf -- '---\nname: bug\nmetadata:\n  type: reference\n---\nref\n'                             > "$MEM/bug.md"
  printf -- '---\nname: done\nmetadata:\n  type: project\n  status: resolved\n---\ndone\n'         > "$MEM/done.md"
  printf -- '---\nname: sup\nmetadata:\n  type: project\n  status: superseded\n---\nx\n'           > "$MEM/sup.md"
  printf -- '---\nname: resfb\nmetadata:\n  type: feedback\n  status: resolved\n---\nx\n'          > "$MEM/resfb.md"
  printf -- '---\nname: closed\nmetadata:\n  type: project\n---\nCLOSED: all done here\n'          > "$MEM/closed.md"
  printf -- '---\nname: live\nmetadata:\n  type: project\n---\nactive work\n'                      > "$MEM/live.md"
  {
    echo "# Memory Index"; echo ""
    for n in fb bug done sup resfb closed live; do echo "- [$n]($n.md) — hook"; done
  } > "$MEM/MEMORY.md"
}

idx() { grep -c '\](' "$MEM/MEMORY.md" 2>/dev/null || echo 0; }

begin_test "memory-prune: dry-run flags resolved+project as auto, touches nothing"
setup_mem
OUT=$(SUPERCHARGER_MEMDIR="$MEM" bash "$TOOL" 2>&1)
{ echo "$OUT" | grep -q '✓ done' && echo "$OUT" | grep -q '✓ sup' && [ "$(idx)" = "7" ]; } && pass \
  || fail "dry-run wrong or mutated index (idx=$(idx)): $OUT"
rm -rf "$(dirname "$MEM")"

begin_test "memory-prune: --apply archives ONLY resolved+project"
setup_mem
SUPERCHARGER_MEMDIR="$MEM" bash "$TOOL" --apply >/dev/null 2>&1
# done + sup archived (2), index 7 -> 5; feedback/reference/live/closed/resfb remain
{ [ "$(idx)" = "5" ] && [ -f "$MEM/archive/done.md" ] && [ -f "$MEM/archive/sup.md" ] \
  && [ -f "$MEM/fb.md" ] && [ -f "$MEM/live.md" ]; } && pass \
  || fail "apply archived wrong set (idx=$(idx))"
rm -rf "$(dirname "$MEM")"

begin_test "memory-prune: resolved-but-not-project is NOT archived"
setup_mem
SUPERCHARGER_MEMDIR="$MEM" bash "$TOOL" --apply >/dev/null 2>&1
{ [ -f "$MEM/resfb.md" ] && [ ! -f "$MEM/archive/resfb.md" ]; } && pass \
  || fail "resolved feedback wrongly archived"
rm -rf "$(dirname "$MEM")"

begin_test "memory-prune: terminal-marker project entry only SUGGESTED, never moved"
setup_mem
OUT=$(SUPERCHARGER_MEMDIR="$MEM" bash "$TOOL" --apply 2>&1)
{ echo "$OUT" | grep -q '? closed' && [ -f "$MEM/closed.md" ] && [ ! -f "$MEM/archive/closed.md" ]; } && pass \
  || fail "terminal-marker entry mishandled: $OUT"
rm -rf "$(dirname "$MEM")"

begin_test "memory-prune: --restore brings entry back and re-adds index line"
setup_mem
SUPERCHARGER_MEMDIR="$MEM" bash "$TOOL" --apply >/dev/null 2>&1
SUPERCHARGER_MEMDIR="$MEM" bash "$TOOL" --restore done >/dev/null 2>&1
{ [ -f "$MEM/done.md" ] && [ ! -f "$MEM/archive/done.md" ] && grep -q 'done.md' "$MEM/MEMORY.md"; } && pass \
  || fail "restore failed (idx=$(idx))"
rm -rf "$(dirname "$MEM")"

begin_test "memory-prune: no memory dir exits cleanly"
OUT=$(SUPERCHARGER_MEMDIR="/nonexistent/xyz/memory" bash "$TOOL" 2>&1); RC=$?
{ [ "$RC" = "0" ] && echo "$OUT" | grep -qi 'No file-memory dir'; } && pass || fail "rc=$RC out=$OUT"

report
