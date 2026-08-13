#!/usr/bin/env bash
# stop-verify must not re-derive a verdict the tree cannot have changed.
#
# It skipped only a CLEAN tree, and that gate stops applying the moment a work
# session touches a file: every turn end from then on re-ran the whole verify
# script, including turns that only read files or answered a question. Across 30
# days of real transcripts it was the most expensive hook in the install — 118
# minutes over 3185 runs, more than double the next — and most of that was the
# same verdict, recomputed.
#
# The two halves this file pins:
#   * a PASS on an unchanged tree is skipped (the saving), and any real change
#     re-runs it (the correctness bound);
#   * a FAIL is re-emitted from cache rather than skipped — the optimisation must
#     not let a failing verification through, which is the whole point of a hook
#     that blocks Stop.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

HOOK="$REPO_DIR/hooks/stop-verify.sh"

echo "=== stop-verify memoization Tests ==="

# The fixture keeps state and output OUTSIDE the repo. A first draft put both
# inside it, so every run changed an untracked file's mtime, the signature
# differed each time, and the cache "never hit" — a fixture defect that reads
# exactly like a product one.
SVM_REPO=$(mktemp -d)
SVM_STATE=$(mktemp -d)
SVM_OUT=$(mktemp -d)
export SUPERCHARGER_STATE="$SVM_STATE"

(
  cd "$SVM_REPO" || exit 1
  git init -q .
  git config user.email t@t
  git config user.name t
  mkdir -p .claude
  printf 'a\n' > f.txt
  printf '#!/bin/sh\nexit 0\n' > .claude/verify.sh
  chmod +x .claude/verify.sh
  git add -A
  git commit -qm init
  printf 'b\n' >> f.txt          # dirty tree — the clean-tree skip no longer applies
) >/dev/null 2>&1

# Runs the hook from the fixture repo, capturing stdout/stderr outside it.
sv_run() {
  ( cd "$SVM_REPO" && printf '{}' | bash "$HOOK" >"$SVM_OUT/o" 2>"$SVM_OUT/e" ) || true
  SV_ERR=$(cat "$SVM_OUT/e" 2>/dev/null || true)
  SV_OUT=$(cat "$SVM_OUT/o" 2>/dev/null || true)
}

begin_test "the first run on a dirty tree actually runs the verify script"
sv_run
printf '%s' "$SV_ERR" | grep -q 'stop-verify: passed' \
  && ! printf '%s' "$SV_ERR" | grep -q 'cached' && pass \
  || fail "expected an uncached pass, got: $SV_ERR"

begin_test "a second run with nothing changed is served from cache"
sv_run
printf '%s' "$SV_ERR" | grep -q 'cached' && pass || fail "re-ran the verify script: $SV_ERR"

begin_test "editing a tracked file re-runs it"
printf 'c\n' >> "$SVM_REPO/f.txt"
sv_run
printf '%s' "$SV_ERR" | grep -q 'cached' && fail "served a stale verdict after an edit" || pass

begin_test "adding an untracked file re-runs it (no diff contains one)"
sv_run   # re-establish the cache for the new tree
printf 'new\n' > "$SVM_REPO/untracked.txt"
sv_run
printf '%s' "$SV_ERR" | grep -q 'cached' && fail "an untracked file did not invalidate the verdict" || pass

# --- a failure must keep blocking ------------------------------------------
begin_test "a failing verify blocks on the first run"
printf '#!/bin/sh\necho "2 tests failed"\nexit 1\n' > "$SVM_REPO/.claude/verify.sh"
chmod +x "$SVM_REPO/.claude/verify.sh"
sv_run
printf '%s' "$SV_OUT" | grep -q '"decision":"block"' && pass || fail "no block emitted: $SV_OUT"

begin_test "and keeps blocking from cache while the tree is unchanged"
sv_run
printf '%s' "$SV_ERR" | grep -q 'cached' \
  && printf '%s' "$SV_OUT" | grep -q '"decision":"block"' && pass \
  || fail "cached failure did not re-block — err: $SV_ERR out: $SV_OUT"

begin_test "the cached block is valid JSON carrying the failure output"
python3 - "$SVM_OUT/o" <<'PYEOF'
import json, sys
d = json.load(open(sys.argv[1]))
assert d.get("decision") == "block", d
assert "2 tests failed" in d.get("reason", ""), d
PYEOF
[ $? -eq 0 ] && pass || fail "cached block is not usable JSON"

begin_test "SUPERCHARGER_VERIFY_MEMO=0 turns the cache off"
SUPERCHARGER_VERIFY_MEMO=0 sv_run
printf '%s' "$SV_ERR" | grep -q 'cached' && fail "memo still active with the opt-out set" || pass

# An overrunning script exits before the verdict; caching there would memoize a
# pass that was never earned.
begin_test "a script killed at the budget is not cached"
printf '#!/bin/sh\nsleep 20\n' > "$SVM_REPO/.claude/verify.sh"
chmod +x "$SVM_REPO/.claude/verify.sh"
SUPERCHARGER_VERIFY_BUDGET_S=1 sv_run
printf '%s' "$SV_ERR" | grep -q 'SKIPPED' || fail "the budget did not fire: $SV_ERR"
SUPERCHARGER_VERIFY_BUDGET_S=1 sv_run
printf '%s' "$SV_ERR" | grep -q 'cached' && fail "an overrun was memoized as a verdict" || pass

rm -rf "$SVM_REPO" "$SVM_STATE" "$SVM_OUT"

report
