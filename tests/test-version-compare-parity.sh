#!/usr/bin/env bash
# Every version comparator in the repo must agree, and must be NEWER-than.
#
# The repo decided "is there an update?" with string tests: `!=` to notify and
# `=` to mean "already up to date". Different is not newer, and the consequences
# were not cosmetic — the remote version comes from the GitHub contents API,
# which lags after a release and served 2.27.14 while master was ahead:
#
#   hooks/update-check.sh   announced "v2.27.20 -> v2.27.14" for 24h after any
#                           successful update (cached remote, stale)
#   tools/update.sh --check announced the same downgrade
#   tools/update.sh         PROCEEDED with it — a silent downgrade that reverts
#                           shipped fixes
#   tools/supercharger.sh   same false notice
#
# Lexical order is also wrong for versions: "2.27.9" sorts after "2.27.10", so a
# string test hid real updates as readily as it invented fake ones.
#
# Four call sites cannot share one definition — hooks do not source lib/, and the
# tools must keep working when lib/ is absent — so the copies are pinned here
# against one table. A comment asking people to keep them in sync is not a test.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

echo "=== version comparator parity Tests ==="

VP=$(mktemp -d)

# newer|older|expected   (expected: 0 = "$1 is newer than $2", 1 = not)
cat > "$VP/cases.txt" <<'CASES'
2.27.21|2.27.20|0
2.27.20|2.27.21|1
2.27.20|2.27.20|1
2.27.10|2.27.9|0
2.27.9|2.27.10|1
2.28.0|2.27.99|0
3.0.0|2.99.99|0
2.27|2.27.0|1
2.27.0|2.27|1
2.27.1|2.27|0
CASES

# Runs a case table through one implementation, printing "a|b|rc" per line.
run_impl() {  # $1 = shell snippet that defines the function
  local defs="$1"
  {
    printf '%s\n' "$defs"
    cat <<'DRIVER'
while IFS='|' read -r A B WANT; do
  [ -z "$A" ] && continue
  if sc_impl "$A" "$B"; then GOT=0; else GOT=1; fi
  printf '%s|%s|%s\n' "$A" "$B" "$GOT"
done
DRIVER
  } > "$VP/driver.sh"
  bash "$VP/driver.sh" < "$VP/cases.txt"
}

# Each implementation, extracted from where it actually lives and renamed so the
# driver is identical for all of them.
extract() {  # $1=file $2=function-name
  python3 - "$1" "$2" <<'PYEOF'
import re, sys
src = open(sys.argv[1], errors="ignore").read()
name = sys.argv[2]
# Definitions may be INDENTED (the tools define theirs inside an `if ! command -v`
# guard). An anchored-at-column-0 pattern returned empty, sc_impl was undefined,
# and two empty outputs compared equal — a vacuous pass.
m = re.search(r'^([ \t]*)%s\(\)\s*\{.*?\n\1\}' % re.escape(name), src, re.S | re.M)
if not m:
    sys.exit("could not extract %s from %s" % (name, sys.argv[1]))
print(m.group(0).replace(name + "()", "sc_impl()", 1))
PYEOF
}

LIB_IMPL=$(extract "$REPO_DIR/lib/utils.sh" sc_version_newer) || true
HOOK_IMPL=$(extract "$REPO_DIR/hooks/update-check.sh" _sc_newer_than) || true
TOOL_IMPL=$(extract "$REPO_DIR/tools/supercharger.sh" sc_version_newer) || true

begin_test "every comparator was found where it is supposed to live"
if [ -n "$LIB_IMPL" ] && [ -n "$HOOK_IMPL" ] && [ -n "$TOOL_IMPL" ]; then
  pass
else
  fail "missing: lib=${#LIB_IMPL} hook=${#HOOK_IMPL} tool=${#TOOL_IMPL} chars"
fi

CASE_COUNT=$(grep -c . "$VP/cases.txt")

# A run that produces no rows means extraction failed; comparing two empty
# outputs would "agree" and prove nothing.
rows_ok() { [ "$(printf '%s\n' "$1" | grep -c .)" = "$CASE_COUNT" ]; }

begin_test "lib/utils.sh comparator answers the table correctly"
LIB_OUT=$(run_impl "$LIB_IMPL")
rows_ok "$LIB_OUT" || fail "lib impl produced $(printf '%s\n' "$LIB_OUT" | grep -c .) of $CASE_COUNT rows"
BAD=$(printf '%s\n' "$LIB_OUT" | while IFS='|' read -r A B GOT; do
  WANT=$(grep "^$A|$B|" "$VP/cases.txt" | cut -d'|' -f3)
  [ "$GOT" = "$WANT" ] || printf '%s>%s got=%s want=%s ' "$A" "$B" "$GOT" "$WANT"
done)
[ -z "$BAD" ] && pass || fail "$BAD"

begin_test "the hook's copy agrees with it, case for case"
HOOK_OUT=$(run_impl "$HOOK_IMPL")
if ! rows_ok "$HOOK_OUT"; then
  fail "hook impl produced $(printf '%s\n' "$HOOK_OUT" | grep -c .) of $CASE_COUNT rows — extraction broken"
else
  DIFF=$(diff <(printf '%s\n' "$LIB_OUT") <(printf '%s\n' "$HOOK_OUT") || true)
  [ -z "$DIFF" ] && pass || fail "hook and lib disagree: $DIFF"
fi

begin_test "the tool's copy agrees with it, case for case"
TOOL_OUT=$(run_impl "$TOOL_IMPL")
if ! rows_ok "$TOOL_OUT"; then
  fail "tool impl produced $(printf '%s\n' "$TOOL_OUT" | grep -c .) of $CASE_COUNT rows — extraction broken"
else
  DIFF=$(diff <(printf '%s\n' "$LIB_OUT") <(printf '%s\n' "$TOOL_OUT") || true)
  [ -z "$DIFF" ] && pass || fail "tool and lib disagree: $DIFF"
fi

# The bug that started this: a string test. Pin that none of them is one.
begin_test "no version decision is a bare string comparison"
BAD=""
for f in "$REPO_DIR/tools/update.sh" "$REPO_DIR/tools/supercharger.sh" "$REPO_DIR/hooks/update-check.sh"; do
  grep -nE '\[ *"\$(REMOTE|REMOTE_VERSION|LOCAL)[^"]*" *(!=|=) *"\$(LOCAL|VERSION|REMOTE)' "$f" 2>/dev/null \
    | grep -v '"\$LOCAL" = "\$REMOTE"' | grep -q . && BAD="$BAD $(basename "$f")"
done
[ -z "$BAD" ] && pass || fail "string version test returned in:$BAD"

rm -rf "$VP"

report
