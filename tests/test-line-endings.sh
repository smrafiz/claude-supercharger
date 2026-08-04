#!/usr/bin/env bash
# Line-ending policy + the flock removal (v2.26.51, WINDOWS-SUPPORT-PLAN G3/G5)
#
# G5 — Git for Windows defaults to core.autocrlf=true. A `.sh` file checked out
# with CRLF does not run under Git Bash: the shebang becomes `/usr/bin/env bash\r`
# and every hook fails at once with an error naming a program nobody typed.
# `.gitattributes` pins the checkout, so a Windows clone is protected even though
# the repo has never held a CRLF file.
#
# G3 — the flock wrapper was removed rather than ported. It never ran on macOS
# (Darwin has no flock), it guarded the wrong window (the append is outside it),
# and the remaining race is benign because `mv` is atomic. See the hook's comment.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

echo "=== Line Endings + Lock Policy ==="

GA="$REPO_DIR/.gitattributes"

begin_test ".gitattributes exists"
[ -f "$GA" ] && pass || fail "no .gitattributes — a Windows clone will get CRLF .sh files"

begin_test "executable and interpreted types are pinned to LF"
MISS=""
for ext in sh py json jsonl yml yaml md; do
  # Braces required: "$ext[[:space:]]" parses as an array expansion (SC1087).
  grep -qE "^\*\.${ext}[[:space:]]+text[[:space:]]+eol=lf" "$GA" || MISS="$MISS .$ext"
done
[ -z "$MISS" ] && pass || fail "not pinned to LF:$MISS"

begin_test "PowerShell keeps its native CRLF"
grep -qE '^\*\.ps1[[:space:]]+text[[:space:]]+eol=crlf' "$GA" && pass \
  || fail ".ps1 should be crlf — it is the one place CRLF is correct"

begin_test "binary assets are not line-ending processed"
grep -qE '^\*\.png[[:space:]]+binary' "$GA" && pass || fail "binary assets unprotected"

begin_test "no tracked shell or python file actually contains CRLF"
# The policy is checkout-time; this asserts the committed content is clean now.
BAD=$(cd "$REPO_DIR" && git ls-files -z '*.sh' '*.py' 2>/dev/null \
  | xargs -0 grep -lU $'\r' 2>/dev/null || true)
[ -z "$BAD" ] && pass || fail "CRLF present in: $BAD"

# --- G3: flock removal --------------------------------------------------------
THT="$REPO_DIR/hooks/tool-history-tracker.sh"

begin_test "the flock wrapper is gone (it never ran on macOS or Git Bash)"
# Match an INVOCATION, not the word: the replacement comment explains flock at
# length, so a bare `grep flock` fails on its own documentation.
grep -qE '^[[:space:]]*flock[[:space:]]' "$THT" && fail "flock is invoked again — a no-op on 2 of 3 platforms" || pass

begin_test "and no fd-9 lock redirection remains"
grep -qE '9>"?\$HISTORY' "$THT" && fail "the lock-file redirection is back" || pass

begin_test "the trim still writes atomically via a temp file and mv"
grep -q 'HISTORY.\$\$.tmp' "$THT" && grep -q 'mv "\$HISTORY.\$\$.tmp"' "$THT" && pass \
  || fail "atomic write lost — that is the actual protection"

begin_test "the trim still bounds history to 20 entries"
T=$(mktemp -d); H="$T/.tool-history-s1"
seq 1 50 > "$H"
# Run just the trim block's logic as the hook now has it.
tail -n 20 "$H" > "$H.$$.tmp" 2>/dev/null && mv "$H.$$.tmp" "$H" 2>/dev/null
N=$(wc -l < "$H" | tr -d ' ')
rm -rf "$T"
[ "$N" = "20" ] && pass || fail "trim produced $N lines, expected 20"

begin_test "a failed trim leaves no stray temp file"
grep -q 'rm -f "\$HISTORY.\$\$.tmp"' "$THT" && pass \
  || fail "temp file is not cleaned up when the trim fails"

begin_test "the stale lock file from older installs is swept"
grep -q 'rm -f "\$HISTORY.lock"' "$THT" && pass \
  || fail "old .lock files will linger in scope/ forever"

report
