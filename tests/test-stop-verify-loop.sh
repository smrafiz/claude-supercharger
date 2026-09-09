#!/usr/bin/env bash
# v4.0.46 — a Stop hook that blocks must be able to STOP blocking.
#
# stop-verify re-blocks whenever the tree signature is unchanged and the cached
# verdict is a failure. That is correct for a failure the agent can fix, and it
# is also the exact signature of a session that can never end: a project whose
# .claude/verify.sh cannot pass — broken environment, missing dependency,
# machine-specific failure — blocked every Stop forever, with no way for the
# user to finish the turn.
#
# Borrowed from flightrules/flightrules, whose lint-on-stop pins this in
# `06-loop-guard-second-block` and `07-loop-guard-releases-after-two`. Seven of
# our Stop hooks read the platform's `stop_hook_active` flag; the two that BLOCK
# did not. The cap here is keyed to the TREE instead, so it resets the moment the
# agent changes something and a genuine fix is never counted against it.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

echo "=== stop-verify loop guard ==="

HOOK="$REPO_DIR/hooks/stop-verify.sh"
ST=$(mktemp -d); mkdir -p "$ST/scope"
PROJ=$(mktemp -d)

git -C "$PROJ" init -q 2>/dev/null
git -C "$PROJ" config user.email t@t.t 2>/dev/null
git -C "$PROJ" config user.name t 2>/dev/null
echo "seed" > "$PROJ/seed.txt"
git -C "$PROJ" add -A 2>/dev/null; git -C "$PROJ" commit -qm init 2>/dev/null
# An uncommitted change, so the "no file changes" skip does not apply.
echo "work in progress" > "$PROJ/wip.txt"
mkdir -p "$PROJ/.claude"
printf '#!/usr/bin/env bash\necho "verify is broken here"\nexit 1\n' > "$PROJ/.claude/verify.sh"
chmod +x "$PROJ/.claude/verify.sh"

run_stop() {
  ( cd "$PROJ" && printf '{"session_id":"s1","stop_hook_active":false}' \
      | SUPERCHARGER_STATE="$ST" bash "$HOOK" 2>/dev/null )
}

blocked() { printf '%s' "$1" | grep -q '"decision":"block"'; }

OUT1=$(run_stop)
OUT2=$(run_stop)
OUT3=$(run_stop)

# CONTROLS FIRST. If the hook never blocks at all — no verify.sh found, the
# clean-tree skip firing, git missing — then "releases on the third" is
# satisfied by a hook that does nothing, which is the defect this file exists to
# catch in the first place.
begin_test "control: a failing verify BLOCKS the first stop"
blocked "$OUT1" && pass || fail "no block on the first stop — every assertion below would be vacuous"

begin_test "control: and blocks again on the second, unchanged tree"
blocked "$OUT2" && pass || fail "the re-block on an unchanged tree stopped working"

begin_test "the third stop is RELEASED, not blocked forever"
blocked "$OUT3" && fail "still blocking after two — the session cannot end" || pass

begin_test "a tree change resets the cap, so a real fix is never penalised"
echo "more work" >> "$PROJ/wip.txt"        # new signature
OUT4=$(run_stop)
blocked "$OUT4" && pass || fail "a changed tree did not re-verify"

rm -rf "$ST" "$PROJ"
report
