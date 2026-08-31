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

report
