#!/usr/bin/env bash
# Claude Supercharger — Claude Code version-floor check
#
# The hook warns when the running Claude Code predates a hook EVENT we register.
# Claude Code does not complain about a registration on an unknown event — it
# does not fire it, warn, or error — so without this check those hooks are
# silently absent. Same failure shape as the v2.29.2 comma-matcher bug.
#
# The load-bearing test here is the DRIFT one at the bottom: it fails when an
# event we register is missing from the hook's floor table, so adopting a new
# event without recording its floor cannot ship unnoticed.

set -uo pipefail
. "${BASH_SOURCE[0]%/*}/helpers.sh"

REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
HOOK="$REPO_DIR/hooks/version-floor-check.sh"
echo "=== Claude Code version floor check ==="

# A stand-in `claude` that reports whatever version we hand it.
_fake_cc() {  # $1 = version -> prints path to the fake binary
  _d=$(mktemp -d)
  printf '#!/bin/sh\necho "%s (Claude Code)"\n' "$1" > "$_d/claude"
  chmod +x "$_d/claude"
  printf '%s' "$_d/claude"
}

# Run the hook against a reported version, in a throwaway state dir.
_run_at() {  # $1 = version -> stderr on stdout
  _s=$(mktemp -d)
  SUPERCHARGER_STATE="$_s" SUPERCHARGER_CC_BIN="$(_fake_cc "$1")" \
    bash "$HOOK" </dev/null 2>&1 >/dev/null || true
}

begin_test "current Claude Code produces no warning"
OUT=$(_run_at "2.1.240")
[ -z "$OUT" ] && pass || fail "expected silence on a current build, got: $OUT"

begin_test "a build below the highest floor warns"
OUT=$(_run_at "2.1.100")
echo "$OUT" | grep -q "DirectoryAdded" && pass || fail "2.1.100 should flag DirectoryAdded: $OUT"

begin_test "warning names the required version, not just the event"
OUT=$(_run_at "2.1.100")
echo "$OUT" | grep -q "needs 2.1.219" && pass || fail "missing the floor version: $OUT"

begin_test "an older build flags strictly more events"
N_NEW=$(_run_at "2.1.100" | grep -c "needs ")
N_OLD=$(_run_at "2.0.50"  | grep -c "needs ")
[ "$N_OLD" -gt "$N_NEW" ] && pass || fail "2.0.50 flagged $N_OLD, 2.1.100 flagged $N_NEW"

begin_test "numeric compare: 2.1.9 is older than 2.1.10, not newer"
# A string compare gets this backwards — 2.1.9 would sort ABOVE 2.1.10 and the
# hook would stay silent on a build that genuinely lacks the event.
OUT=$(_run_at "2.1.9")
echo "$OUT" | grep -q "Setup (needs 2.1.10)" && pass || fail "2.1.9 must be treated as older than 2.1.10: $OUT"

begin_test "security-relevant losses are marked as such"
OUT=$(_run_at "2.1.100")
echo "$OUT" | grep -q "SECURITY: secret redaction" && pass || fail "MessageDisplay loss not marked SECURITY: $OUT"

begin_test "warning states that core protection is unaffected"
# Users must not read this and conclude their guards are off; PreToolUse and
# PostToolUse are baseline events and keep running.
OUT=$(_run_at "2.0.50")
echo "$OUT" | grep -q "Core protection is unaffected" && pass || fail "missing the reassurance line: $OUT"

begin_test "opt-out env var silences it"
S=$(mktemp -d)
OUT=$(SUPERCHARGER_STATE="$S" SUPERCHARGER_CC_BIN="$(_fake_cc 2.0.50)" \
      SUPERCHARGER_NO_VERSION_FLOOR_CHECK=1 bash "$HOOK" </dev/null 2>&1 >/dev/null || true)
[ -z "$OUT" ] && pass || fail "opt-out ignored: $OUT"

begin_test "version is cached — no second 'claude --version' fork"
T=$(mktemp -d); S=$(mktemp -d)
printf '#!/bin/sh\necho called >> %s/calls\necho "2.1.100 (Claude Code)"\n' "$T" > "$T/claude"
chmod +x "$T/claude"; : > "$T/calls"
for _ in 1 2 3; do
  SUPERCHARGER_STATE="$S" SUPERCHARGER_CC_BIN="$T/claude" bash "$HOOK" </dev/null >/dev/null 2>&1 || true
done
CALLS=$(wc -l < "$T/calls" | tr -d ' ')
[ "$CALLS" = "1" ] && pass || fail "expected 1 version fork across 3 runs, got $CALLS"

begin_test "cache invalidates when the claude binary changes"
printf '#!/bin/sh\necho called >> %s/calls\necho "2.1.240 (Claude Code)"\n' "$T" > "$T/claude"
chmod +x "$T/claude"
SUPERCHARGER_STATE="$S" SUPERCHARGER_CC_BIN="$T/claude" bash "$HOOK" </dev/null >/dev/null 2>&1 || true
CALLS=$(wc -l < "$T/calls" | tr -d ' ')
[ "$CALLS" = "2" ] && pass || fail "upgrade should re-detect; forks=$CALLS"

begin_test "warns at most once a day for the same version"
T2=$(mktemp -d); S2=$(mktemp -d)
printf '#!/bin/sh\necho "2.0.50 (Claude Code)"\n' > "$T2/claude"; chmod +x "$T2/claude"
A=$(SUPERCHARGER_STATE="$S2" SUPERCHARGER_CC_BIN="$T2/claude" bash "$HOOK" </dev/null 2>&1 >/dev/null || true)
B=$(SUPERCHARGER_STATE="$S2" SUPERCHARGER_CC_BIN="$T2/claude" bash "$HOOK" </dev/null 2>&1 >/dev/null || true)
[ -n "$A" ] && [ -z "$B" ] && pass || fail "throttle broken (first='$A' second='$B')"

begin_test "fails open when claude is not on PATH"
S3=$(mktemp -d)
OUT=$(PATH=/usr/bin:/bin SUPERCHARGER_STATE="$S3" SUPERCHARGER_CC_BIN="" \
      /bin/bash "$HOOK" </dev/null 2>&1); RC=$?
[ "$RC" = "0" ] && [ -z "$OUT" ] && pass || fail "should be silent+0, got rc=$RC out=$OUT"

begin_test "fails open on an unparseable version string"
T4=$(mktemp -d); S4=$(mktemp -d)
printf '#!/bin/sh\necho "not-a-version"\n' > "$T4/claude"; chmod +x "$T4/claude"
OUT=$(SUPERCHARGER_STATE="$S4" SUPERCHARGER_CC_BIN="$T4/claude" bash "$HOOK" </dev/null 2>&1); RC=$?
[ "$RC" = "0" ] && [ -z "$OUT" ] && pass || fail "should be silent+0, got rc=$RC out=$OUT"

# ── Drift guard ───────────────────────────────────────────────────────────────
# Every event we register must be either in the hook's floor table or on the
# baseline list. Without this, adopting a newly-shipped event silently reopens
# exactly the hole this hook exists to close.
begin_test "every registered event is either floored or baseline"
DRIFT=$(python3 - "$REPO_DIR" <<'PY'
import json, re, sys, pathlib
repo = pathlib.Path(sys.argv[1])
events = set(json.loads((repo / "hooks/hooks.json").read_text()).get("hooks", {}).keys())
hook = (repo / "hooks/version-floor-check.sh").read_text()
floored = set(re.findall(r"^([A-Za-z]+)\|\d+\.\d+\.\d+\|", hook, re.M))
m = re.search(r"_BASELINE='([^']*)'", hook)
baseline = set(m.group(1).split()) if m else set()
missing = sorted(events - floored - baseline)
print(" ".join(missing))
PY
)
[ -z "$DRIFT" ] && pass || fail "events registered but absent from the floor table and baseline list: $DRIFT"

report
