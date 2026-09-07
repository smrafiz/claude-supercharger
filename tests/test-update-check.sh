#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

HOOK="$REPO_DIR/hooks/update-check.sh"

echo "=== Update Check Tests ==="

begin_test "update-check: respects SUPERCHARGER_NO_UPDATE_CHECK=1"
setup_test_home
mkdir -p "$HOME/.claude/supercharger"
echo "2.6.77" > "$HOME/.claude/supercharger/.version"
OUT=$(SUPERCHARGER_NO_UPDATE_CHECK=1 bash "$HOOK" 2>&1)
EXIT=$?
teardown_test_home
[ "$EXIT" -eq 0 ] && [ -z "$OUT" ] && pass || fail "expected silent exit, exit=$EXIT out=$OUT"

begin_test "update-check: exits 0 with no .version file"
setup_test_home
mkdir -p "$HOME/.claude/supercharger"
OUT=$(bash "$HOOK" 2>&1)
EXIT=$?
teardown_test_home
[ "$EXIT" -eq 0 ] && pass || fail "exit=$EXIT out=$OUT"

begin_test "update-check: uses cache when fresh (<24h)"
setup_test_home
mkdir -p "$HOME/.claude/supercharger"
echo "2.6.77" > "$HOME/.claude/supercharger/.version"
echo "2.6.77" > "$HOME/.claude/supercharger/.update-cache"
# Force cache freshness — touch to now
touch "$HOME/.claude/supercharger/.update-cache"
START=$(date +%s)
OUT=$(SUPERCHARGER_NO_UPDATE_CHECK=0 bash "$HOOK" 2>&1)
END=$(date +%s)
EXIT=$?
teardown_test_home
# Should return fast (no network) — and silent (LOCAL == REMOTE)
[ "$EXIT" -eq 0 ] && [ -z "$OUT" ] && [ "$((END - START))" -lt 3 ] && pass || fail "exit=$EXIT out=$OUT time=$((END - START))s"

begin_test "update-check: prints banner when cache shows newer version"
setup_test_home
mkdir -p "$HOME/.claude/supercharger"
echo "2.6.77" > "$HOME/.claude/supercharger/.version"
echo "9.9.9" > "$HOME/.claude/supercharger/.update-cache"
touch "$HOME/.claude/supercharger/.update-cache"
OUT=$(bash "$HOOK" 2>&1)
EXIT=$?
teardown_test_home
# v4.0.34: the notice is a systemMessage payload, not a raw banner — that is
# the only channel a SessionStart hook renders through. Assert the FIELD, not
# the words, so the test fails if it regresses to an echo.
[ "$EXIT" -eq 0 ] && printf '%s' "$OUT" | python3 -c "
import sys, json
d = json.loads(sys.stdin.read())
assert 'Update available' in d['systemMessage'], d
" 2>/dev/null && pass || fail "no systemMessage notice, exit=$EXIT out=$OUT"

begin_test "update-check: cache miss when stale (>24h)"
setup_test_home
mkdir -p "$HOME/.claude/supercharger"
echo "2.6.77" > "$HOME/.claude/supercharger/.version"
echo "2.6.77" > "$HOME/.claude/supercharger/.update-cache"
# Backdate cache to >24h ago
touch -t 202001010000 "$HOME/.claude/supercharger/.update-cache" 2>/dev/null
# Hook should NOT exit on cache (proceed to fetch) — but the fetch is
# backgrounded and non-blocking, so the foreground still returns ~immediately.
START=$(date +%s)
OUT=$(timeout 6 bash "$HOOK" 2>&1)
END=$(date +%s)
EXIT=$?
teardown_test_home
# Background fetch shouldn't block past a few seconds
[ "$((END - START))" -lt 6 ] && pass || fail "stale path blocked too long: $((END - START))s"

# --- v4.0.32: the banner must land on STDOUT ---------------------------------
# For the life of this hook the banner went to stderr and was never delivered to
# anyone. The check ran, the network call completed, the cache was written, the
# comparison took the banner branch — and the output went nowhere. Proven on
# 2026-09-07 against a live install: the cache regenerated to 4.0.31 against an
# installed 4.0.30 and the user saw nothing.
#
# Twelve tests above assert the banner is PRODUCED. Every one of them captured
# both streams together, so all twelve passed while the feature did nothing.
# That is the whole lesson: assert the CHANNEL, not just the content.
# [[diagnostic-must-reach-observer]]
_UCS_TD=$(mktemp -d); mkdir -p "$_UCS_TD/state"
printf '4.0.20\n' > "$_UCS_TD/state/.version"
printf '4.0.31\n' > "$_UCS_TD/state/.update-cache"
_ucs() { SUPERCHARGER_STATE="$_UCS_TD/state" SUPERCHARGER_HOME="$REPO_DIR" \
           bash "$REPO_DIR/hooks/update-check.sh" "$@"; }

begin_test "update-check: the notice payload is on STDOUT"
[ -n "$(_ucs 2>/dev/null)" ] && pass || fail "nothing on stdout — the notice is undeliverable"

begin_test "update-check: and NOT on stderr"
# The control. Without it the test above also passes when the banner is on both.
[ -z "$(_ucs 2>&1 1>/dev/null)" ] && pass || fail "still writing to stderr, which SessionStart does not deliver"

begin_test "update-check: no stderr writes remain in the source"
! grep -q '>&2' "$REPO_DIR/hooks/update-check.sh" && pass \
  || fail "a >&2 came back — SessionStart stderr is not delivered"
rm -rf "$_UCS_TD"

begin_test "the /memory-prune nudge is a nudge, not a trace, so it is on stdout"
# Second instance of the same defect, found by auditing siblings rather than
# assuming one. The two "injected ..." lines in that hook stay on stderr on
# purpose — they are traces. A blanket stderr ban would be the wrong fix.
grep -q 'run /memory-prune to archive\."$' "$REPO_DIR/hooks/session-memory-inject.sh" && pass \
  || fail "the memory-prune nudge is back on stderr"

# --- v4.0.33: the banner must be rendered, not merely written ----------------
# v4.0.32 moved it from stderr to stdout and it STILL did not appear. Measured
# 2026-09-07 on a live install (cache 4.0.33 vs installed 4.0.32, so the banner
# branch provably fired): an ASYNC hook's stdout is not rendered in the
# terminal. In the same session, config-scan.sh and project-config.sh — both
# SYNC — rendered as "SessionStart:startup says: ...".
#
# Sync costs nothing here: the cache-hit path is a file read, and the cache-MISS
# path backgrounds its own network call, so the foreground never waits on the
# network.
#
# The earlier reasoning that exonerated `async` was wrong for an instructive
# reason: learn-from-blocks.sh is async and its [BLOCKS] output reaches the
# MODEL. Model-visible is not terminal-visible. [[diagnostic-must-reach-observer]]

begin_test "update-check is NOT registered async — async stdout is never rendered"
grep -q 'update-check.sh|async' "$REPO_DIR/lib/hooks.sh" \
  && fail "registered async again; the banner will print and render nowhere" || pass

begin_test "and the generated hooks.json carries no async flag for it"
python3 - "$REPO_DIR/hooks/hooks.json" <<'PY'
import json,sys
d=json.load(open(sys.argv[1]))
for ev,arr in d.get('hooks',{}).items():
    for e in arr:
        for h in e.get('hooks',[]):
            if 'update-check' in str(h.get('command','')) and h.get('async'):
                sys.exit(1)
sys.exit(0)
PY
[ $? -eq 0 ] && pass || fail "hooks.json still marks update-check async"

begin_test "the backgrounded fetch does not try to print a banner"
# Its stdout is orphaned by `} &`, so a print there is unreachable either way.
# Match any notice wording, not one phrase — a re-added banner with different
# words would be just as unreachable and just as invisible.
_UCA=$(sed -n '/^{$/,/^} &$/p' "$REPO_DIR/hooks/update-check.sh" | grep -cE 'systemMessage|Update available|Supercharger update')
[ "$_UCA" = "0" ] && pass || fail "unreachable banner is back inside the backgrounded block"

# --- v4.0.34: use the channel that actually renders --------------------------
# Three releases each fixed the wrong layer: stderr -> stdout (v4.0.32), then
# async -> sync (v4.0.33). Neither rendered, because raw stdout from a
# SessionStart hook is not shown in the terminal AT ALL. The channel that
# produces "SessionStart:startup says: ..." is a `systemMessage` JSON field.
#
# The proof was a clean A/B inside this repo, same event, all along:
#   config-scan.sh:369     systemMessage  -> renders
#   project-config.sh:442  systemMessage  -> renders
#   update-check.sh        echo           -> did not
# Nothing asserted the parity, so nothing caught it.

begin_test "the user-facing notice uses systemMessage, like every hook that renders"
grep -q 'systemMessage' "$REPO_DIR/hooks/update-check.sh" && pass \
  || fail "back to raw stdout, which SessionStart does not render"

begin_test "and it emits ONE valid JSON object, not a JSON-ish string"
# A malformed payload is silently dropped, which looks exactly like the bug
# this whole arc was about.
_UCJ_TD=$(mktemp -d); mkdir -p "$_UCJ_TD/s"
printf '1.0.0\n' > "$_UCJ_TD/s/.version"; printf '9.9.9\n' > "$_UCJ_TD/s/.update-cache"
SUPERCHARGER_STATE="$_UCJ_TD/s" SUPERCHARGER_HOME="$REPO_DIR" \
  bash "$REPO_DIR/hooks/update-check.sh" 2>/dev/null \
  | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null && pass \
  || fail "output is not a single valid JSON object"
rm -rf "$_UCJ_TD"

begin_test "every SessionStart hook that speaks to the USER uses systemMessage"
# Guard the class, not the instance. A hook whose whole job is a user notice
# and which echoes instead will never be seen, and nothing else would say so.
_UCP_BAD=""
for _h in config-scan project-config version-floor-check update-check; do
  grep -q 'systemMessage' "$REPO_DIR/hooks/$_h.sh" || _UCP_BAD="$_UCP_BAD $_h"
done
[ -z "$_UCP_BAD" ] && pass || fail "user-facing SessionStart hooks not on the rendering channel:$_UCP_BAD"

report
