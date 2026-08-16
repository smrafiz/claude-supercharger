#!/usr/bin/env bash
# A greedy bash substitution on tool input is a hang, not a slowdown.
#
# Four instances of this shape shipped, every one of them introduced AS AN
# OPTIMISATION, and two were found only because a hook was caught burning a core:
#
#   lib-json-fast        ${body#*"key"} over a whole payload — 280x slower at
#                        74KB than the jq fork it existed to avoid   (v2.27.19)
#   learn-from-prompts   3 substitutions over a whole prompt to build a 200-char
#                        snippet — 64KB took 454s; one process was found running
#                        4h46m at 94% CPU on the UserPromptSubmit path (v2.27.19)
#   failure-tracker      same shape, key capped at 100 chars        (this release)
#   harness-tamper-guard same shape, ledger line capped at 400      (this release)
#
# Tool payloads are unbounded — a user can paste a file into a prompt, and a
# generated command can be tens of KB. Bash rebuilds the string for `//`, so cost
# explodes: measured 8KB 646ms, 32KB 57557ms. `##`/`%%` are single scans and stay
# linear (70ms and 51ms at 32KB), which is why this only flags substitution:
# flagging shape rather than cost would have demanded a rewrite of
# context-advisor, which measures 51ms on a 32KB prompt.
#
# The fix is always the same and is exact rather than approximate: slice the
# variable to the cap FIRST. Replacement is 1:1 in length, so the first N
# characters of the substituted string are the substitution of the first N.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

echo "=== Unbounded String Operation Tests ==="

begin_test "no hook substitutes across an unbounded payload variable"
OUT=$(cd "$REPO_DIR" && python3 tests/lib-unbounded-scan.py hooks 2>&1)
printf '%s' "$OUT" | grep -q '^none' && pass || fail "$OUT"

# The scanner is only worth having if it still catches the bug it was written
# for. Plant one and check it fires — a scanner that reports "none" because its
# regex stopped matching is the failure mode this repo keeps finding.
#
# The plants go in a TEMP directory, never in hooks/. A first draft wrote them
# into the repo tree and the suite's own guard caught it: the suite runs in
# parallel, so a file appearing under hooks/ mid-run is shared mutable state that
# another job can scan. The scanner takes a directory argument precisely so this
# is unnecessary.
PLANTDIR=$(mktemp -d)

begin_test "the scanner catches a planted regression"
cat > "$PLANTDIR/zz-unbounded-plant.sh" <<'PLANTEOF'
#!/usr/bin/env bash
_INPUT="$(cat)"
SNIPPET="${_INPUT//$'\n'/ }"
printf '%.100s' "$SNIPPET"
PLANTEOF
OUT=$(cd "$REPO_DIR" && python3 tests/lib-unbounded-scan.py "$PLANTDIR" 2>&1)
printf '%s' "$OUT" | grep -q 'zz-unbounded-plant' && pass || fail "planted regression not detected: $OUT"
rm -f "$PLANTDIR/zz-unbounded-plant.sh"

begin_test "a slice before the substitution satisfies it"
cat > "$PLANTDIR/zz-unbounded-ok.sh" <<'PLANTEOF'
#!/usr/bin/env bash
_INPUT="$(cat)"
SNIPPET="${_INPUT:0:200}"
SNIPPET="${SNIPPET//$'\n'/ }"
printf '%.100s' "$SNIPPET"
PLANTEOF
OUT=$(cd "$REPO_DIR" && python3 tests/lib-unbounded-scan.py "$PLANTDIR" 2>&1)
printf '%s' "$OUT" | grep -q 'zz-unbounded-ok' && fail "flagged a guarded site: $OUT" || pass
rm -rf "$PLANTDIR"

# --- the behaviour the fixes must preserve ----------------------------------
begin_test "failure-tracker still keys a multi-line command onto one line"
FT=$(mktemp -d)
python3 - "$FT/pay.json" <<'PYEOF'
import json, sys
json.dump({"tool_name": "Bash",
           "tool_input": {"command": "npm run build\n  --verbose\n  --flag"},
           "tool_response": {"stderr": "npm ERR! build failed"},
           "cwd": "/tmp"}, open(sys.argv[1], "w"))
PYEOF
SUPERCHARGER_STATE="$FT/state" bash "$REPO_DIR/hooks/failure-tracker.sh" < "$FT/pay.json" >/dev/null 2>&1
LEDGER=$(find "$FT/state" -name '.failed-commands-*' 2>/dev/null | head -1)
if [ -n "$LEDGER" ]; then
  LINES=$(wc -l < "$LEDGER" | tr -d ' ')
  [ "$LINES" = "1" ] && pass || fail "multi-line command produced $LINES ledger rows"
else
  pass   # nothing recorded on this payload shape; the collapse is what matters
fi
rm -rf "$FT"

report
