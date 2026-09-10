#!/usr/bin/env bash
# Suite for tools/claude-check.sh — the registration reporting added in v4.0.1.
#
# install.sh prints "Run claude-check to verify installation", so this is the
# tool a user reaches for when they suspect something is wrong. It already
# reported a COUNT, which reads fine until you know what the count should be:
# during the 2026-08-30 null-matcher incident it would have said "122
# Supercharger hook(s) registered" with no hint that 154 was expected, and 27 of
# those 122 were entries Claude Code ignores.
#
# Scoped deliberately to that behaviour. The other 500 lines of this tool are
# not covered here; this file exists because the registration report is what a
# user trusts when deciding whether they are protected.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

TOOL="$REPO_DIR/tools/claude-check.sh"
# Assembled so this file never contains the literal tag it asserts on.
TAG='#''supercharger'

# $1 = live registrations, $2 = inert (null-matcher) ones, $3 = stamp or "" for none
_mkinstall() {
  local h sc
  h=$(mktemp -d); sc="$h/.claude/supercharger"
  mkdir -p "$sc/hooks" "$sc/scope"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$sc/hooks/safety.sh"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$sc/hooks/git-safety.sh"
  printf '4.0.0\n' > "$sc/.version"
  [ -n "$3" ] && printf '%s\n' "$3" > "$sc/.registration-count"
  LIVE="$1" NULLED="$2" SC="$sc" OUT="$h/.claude/settings.json" TAG="$TAG" python3 - <<'PY'
import json, os
sc, tag = os.environ['SC'], os.environ['TAG']
live = {"matcher": "Bash", "hooks": [{"type": "command",
        "command": os.path.join(sc, "hooks", "safety.sh") + " " + tag}]}
nulled = {"matcher": None, "hooks": [{"type": "command",
          "command": os.path.join(sc, "hooks", "git-safety.sh") + " " + tag}]}
h = {}
if int(os.environ['LIVE']):   h["PreToolUse"] = [live] * int(os.environ['LIVE'])
if int(os.environ['NULLED']): h["SessionStart"] = [nulled] * int(os.environ['NULLED'])
json.dump({"hooks": h}, open(os.environ['OUT'], "w"), indent=2)
PY
  printf '%s' "$h"
}
_run() { HOME="$1" bash "$TOOL" 2>&1 | sed 's/\x1b\[[0-9;]*m//g'; }

echo "=== claude-check registration reporting ==="

begin_test "claude-check: reports a SHORTFALL against the install stamp"
# 122 registered reads healthy until the tool knows 154 was left behind.
H=$(_mkinstall 95 27 154)
_run "$H" | grep -q '32 registration(s) MISSING' && pass || fail "did not report the shortfall"
rm -rf "$H"

begin_test "claude-check: names registrations that are present but INERT"
H=$(_mkinstall 95 27 154)
_run "$H" | grep -q '27 registration(s) present but INERT' && pass || fail "did not flag null-matcher entries"
rm -rf "$H"

begin_test "claude-check: the health score does not contradict the shortfall"
# The bands topped out at 50, so an install missing a third of its guards still
# scored 25/25 while the line above it said MISSING. The reader believes the number.
H=$(_mkinstall 95 27 154)
_run "$H" | grep -qE 'Hooks +25/25' && fail "scored a perfect 25/25 while reporting a shortfall" || pass
rm -rf "$H"

begin_test "claude-check: silent about registration on a complete install"
H=$(_mkinstall 154 0 154)
OUT=$(_run "$H")
{ printf '%s' "$OUT" | grep -q 'MISSING'; } && fail "cried wolf on a complete install" || {
  printf '%s' "$OUT" | grep -qE 'Hooks +25/25' && pass || fail "a complete install lost score: $(printf '%s' "$OUT" | grep Hooks)"
}
rm -rf "$H"

begin_test "claude-check: fails OPEN when the install predates the stamp"
# Older installs have no .registration-count. They must not be reported broken.
H=$(_mkinstall 154 0 "")
_run "$H" | grep -q 'MISSING' && fail "warned without a stamp to compare against" || pass
rm -rf "$H"

begin_test "claude-check: does not warn when MORE are registered than stamped"
H=$(_mkinstall 160 0 154)
_run "$H" | grep -q 'MISSING' && fail "cried wolf when registrations exceeded the stamp" || pass
rm -rf "$H"

begin_test "claude-check: a garbage stamp is ignored rather than believed"
H=$(_mkinstall 154 0 "not-a-number")
_run "$H" | grep -q 'MISSING' && fail "acted on an unparseable stamp" || pass
rm -rf "$H"

begin_test "claude-check: SAYS SO when it cannot verify completeness"
# The tool prints a health score, so people read it as a verdict. A guard is
# right to fail open; an oracle that stays silent about what it could not check
# is issuing a clean bill of health it was not able to issue.
H=$(_mkinstall 154 0 "")
_run "$H" | grep -q 'Completeness unverified' && pass || fail "silently omitted the completeness check"
rm -rf "$H"

begin_test "claude-check: does NOT say that when the stamp is present"
H=$(_mkinstall 154 0 154)
_run "$H" | grep -q 'Completeness unverified' && fail "claimed unverified with a stamp present" || pass
rm -rf "$H"

# --- v4.0.11: the deep scan can be cut short, and that used to be invisible ----
#
# safety-detect.py kills itself on a wall-clock overrun and exits 0 with no
# output; safety.sh's `|| PY_REASON=""` flattens that into the same silent allow
# as a clean scan. Measured 2026-09-01 by keeping the exit code and stderr the
# hook normally discards: about 0.6% of calls under heavy parallel load, every
# captured failure `rc=0 cats=[] stderr=(empty)`. The archive and secret-directory
# rules exist ONLY in that file, so while it is cut short they do not run.
#
# The fail-open is correct and stays. The oracle staying quiet about it is not —
# same argument as the stamp branch above.

begin_test "claude-check: reports that the deep scan was cut short"
H=$(_mkinstall 154 0 154)
printf '1788253245 0.500\n1788253299 0.500\n' > "$H/.claude/supercharger/scope/.detect-overruns"
_run "$H" | grep -q 'Deep scan cut short 2 time' && pass || fail "overrun log present but never reported"
rm -rf "$H"

begin_test "claude-check: silent about overruns when there were none"
# The cry-wolf half. A healthy install must not carry a warning about a fail-open
# that never happened, or the line stops meaning anything.
H=$(_mkinstall 154 0 154)
_run "$H" | grep -q 'Deep scan cut short' && fail "warned with no overrun log" || pass
rm -rf "$H"

begin_test "claude-check: an empty overrun log is not a warning"
# grep -c on an empty file returns 0; the case guard must treat that as nothing
# to say rather than printing "cut short 0 time(s)".
H=$(_mkinstall 154 0 154)
: > "$H/.claude/supercharger/scope/.detect-overruns"
_run "$H" | grep -q 'Deep scan cut short' && fail "warned on an empty overrun log" || pass
rm -rf "$H"

# --- v4.0.48: the two cost levers the platform added and we never surfaced ----
# maxEffortLevel (Claude Code 2.1.267) caps effort on every provider;
# autoCompactThreshold is the deterministic form of the "suggest /compact at
# 70%" rule our own CLAUDE.md asks the MODEL to remember. Both were referenced
# in 0 of our files before this.
#
# The POSITIVE CONTROL is the point of this block. An advisory that always
# prints is decoration — it has to disappear when the setting is actually there,
# or nobody can tell the check from a banner.
_ck_setting() { # $1=json fragment for settings.json -> full doctor output
  local h sc; h=$(mktemp -d); sc="$h/.claude/supercharger"
  mkdir -p "$sc/hooks" "$sc/scope"; printf '4.0.0\n' > "$sc/.version"
  printf '%s' "$1" > "$h/.claude/settings.json"
  HOME="$h" bash "$TOOL" 2>&1 | sed 's/\x1b\[[0-9;]*m//g'
  rm -rf "$h"
}

begin_test "doctor: advises maxEffortLevel when it is absent"
_ck_setting '{"hooks":{}}' | grep -q 'maxEffortLevel not set' && pass \
  || fail "no advisory for a missing effort cap"

begin_test "CONTROL: and stops advising once it IS set (top level)"
_ck_setting '{"maxEffortLevel":"medium","hooks":{}}' | grep -q 'maxEffortLevel not set' \
  && fail "advisory still fires with the setting present — it is decoration" || pass

begin_test "CONTROL: per-model under modelSettings counts too"
# The binary's own text: "maxEffortLevel replaces it per model." Reading only the
# top-level key would nag every user who configured it the documented way.
_ck_setting '{"modelSettings":{"claude-opus-5":{"maxEffortLevel":"low"}},"hooks":{}}' \
  | grep -q 'maxEffortLevel not set' && fail "per-model form not recognised" || pass

begin_test "doctor: advises autoCompactThreshold when it is absent"
_ck_setting '{"hooks":{}}' | grep -q 'autoCompactThreshold not set' && pass \
  || fail "no advisory for a missing compaction threshold"

begin_test "CONTROL: and stops advising once it IS set"
_ck_setting '{"autoCompactThreshold":80,"hooks":{}}' | grep -q 'autoCompactThreshold not set' \
  && fail "advisory still fires with the setting present" || pass

begin_test "doctor: an unparseable settings.json is reported as UNKNOWN, not as 0 hooks"
# The fallback that kept the script alive (`|| echo "0 0"`) was also the one that
# made it lie: `settings.json valid — 0 Supercharger hook(s) registered` for a
# file Claude Code will refuse to load. 0 hooks in a good file and a file that
# cannot be read produced the same number, and the message said "valid" either
# way. An oracle that cannot tell those apart is worse than one that stops.
_CK_BAD=$(_ck_setting '{"maxEffortLevel":')
printf '%s' "$_CK_BAD" | grep -q 'could NOT be parsed' && pass \
  || fail "reported a broken settings.json as valid"

begin_test "CONTROL: a VALID settings.json still says valid"
# Without this, the assertion above is satisfied by a doctor that calls every
# file unparseable.
_ck_setting '{"hooks":{}}' | grep -q 'settings.json valid' && pass \
  || fail "a good file is now reported as broken"

begin_test "a malformed settings.json does not crash the doctor"
# This file has crashed twice before on input it could not parse (the
# fresh-install SUMMARY_COUNT case, and the no-match greps). The python here
# already has `|| echo 0|0|0|0`; this pins it.
_CK_OUT=$(_ck_setting '{"maxEffortLevel":')
printf '%s' "$_CK_OUT" | grep -q 'Paste this if you are asking for help' && pass \
  || fail "doctor did not reach its verdict on malformed settings"

report
