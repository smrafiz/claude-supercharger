#!/usr/bin/env bash
# tests/run.sh TEST_SHARD=i/n: CI splits the Windows suite across 4 machines. The
# shards must cover every file exactly once, or a file silently leaves the gate.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

echo "=== Test Shard Tests ==="

# A throwaway tests/ dir: run.sh, its helpers, and 7 trivial test files.
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/tests"
cp "$REPO_DIR/tests/run.sh" "$REPO_DIR/tests/helpers.sh" "$T/tests/"
for n in a b c d e f g; do
  printf '#!/usr/bin/env bash\nsource "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"\nbegin_test "%s"\npass\nreport\n' "$n" > "$T/tests/test-$n.sh"
done
_files() { TEST_JOBS=2 "$@" bash "$T/tests/run.sh" 2>/dev/null | sed -n 's/^--- \(.*\) ---$/\1/p'; }

ALL=$(_files env | sort)
SHARDS=$(for i in 1 2 3 4; do _files env TEST_SHARD="$i/4"; done | sort)

begin_test "the 4 shards together run every file"
[ "$SHARDS" = "$ALL" ] && pass || fail "all: $(echo $ALL) shards: $(echo $SHARDS)"

begin_test "no file runs in two shards"
[ -z "$(printf '%s\n' "$SHARDS" | uniq -d)" ] && pass || fail "duplicates: $(printf '%s\n' "$SHARDS" | uniq -d)"

begin_test "a shard runs only its share"
N=$(_files env TEST_SHARD=1/4 | wc -l | tr -d ' ')
[ "$N" = 2 ] && pass || fail "shard 1/4 of 7 files ran $N, want 2"

begin_test "a shard total counts only its own files"
TOT=$(TEST_JOBS=2 TEST_SHARD=2/4 bash "$T/tests/run.sh" 2>/dev/null | grep '^Total:')
[ "$TOT" = "Total: 2 passed, 0 failed" ] && pass || fail "got: $TOT"

begin_test "an invalid TEST_SHARD is refused, not treated as 'run everything'"
TEST_SHARD=5/4 bash "$T/tests/run.sh" >/dev/null 2>&1; R1=$?
TEST_SHARD=x bash "$T/tests/run.sh" >/dev/null 2>&1; R2=$?
{ [ "$R1" = 2 ] && [ "$R2" = 2 ]; } && pass || fail "5/4 rc=$R1, x rc=$R2 (want 2)"

report
