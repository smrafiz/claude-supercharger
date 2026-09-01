#!/usr/bin/env bash
# Suite for hooks/guard-registration-check.sh (v2.29.22)
#
# An install that silently stops registering is indistinguishable from a working
# one — and project-config announces "Guardrails are on" either way. Measured
# before this hook existed: with an empty hooks key, every other SessionStart
# hook stayed silent while that claim still went out. This asserts the check
# closes that, and — more importantly — that it does NOT cry wolf, because a
# false "you are unprotected" warning is what trains people to disable it.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

HOOK="$REPO_DIR/hooks/guard-registration-check.sh"
# Assembled so this file never contains the literal tag it searches for, which
# would otherwise make the repo's own settings match by accident.
TAG='#''supercharger'

_mkhome() {  # $1 = settings body, or "" for no file; $2 = optional stamp value
  local h; h=$(mktemp -d); mkdir -p "$h/.claude" "$h/.claude/supercharger"
  [ -n "$1" ] && printf '%s\n' "$1" > "$h/.claude/settings.json"
  [ -n "${2:-}" ] && printf '%s\n' "$2" > "$h/.claude/supercharger/.registration-count"
  printf '%s' "$h"
}
# N registrations, each carrying the tag, as one settings body.
_settings_with() {  # $1 = how many
  local i out=""
  for ((i = 0; i < $1; i++)); do
    out="$out{\"hooks\":[{\"command\":\"h$i $TAG\"}]},"
  done
  printf '{"hooks":{"PreToolUse":[%s]}}' "${out%,}"
}
_warns() {  # $1 = home, $2 = optional CLAUDE_PLUGIN_ROOT -> "warns"/"silent"
  local out
  if [ -n "${2:-}" ]; then
    out=$(printf '{}' | HOME="$1" CLAUDE_PLUGIN_ROOT="$2" bash "$HOOK" 2>/dev/null)
  else
    out=$(printf '{}' | HOME="$1" bash "$HOOK" 2>/dev/null)
  fi
  [ -z "$out" ] && echo "silent" || echo "warns"
}

begin_test "guard-reg: warns when the hooks key is empty"
H=$(_mkhome '{"hooks":{}}')
[ "$(_warns "$H")" = "warns" ] && pass || fail "did not warn on an empty hooks key"
rm -rf "$H"

begin_test "guard-reg: warns when only foreign hooks are registered"
# Someone else's hooks present is not our hooks present.
H=$(_mkhome '{"hooks":{"PreToolUse":[{"hooks":[{"command":"other-tool"}]}]}}')
[ "$(_warns "$H")" = "warns" ] && pass || fail "did not warn when only foreign hooks exist"
rm -rf "$H"

begin_test "guard-reg: silent when our hooks ARE registered"
H=$(_mkhome "{\"hooks\":{\"PreToolUse\":[{\"hooks\":[{\"command\":\"x $TAG\"}]}]}}")
[ "$(_warns "$H")" = "silent" ] && pass || fail "false positive on a healthy install"
rm -rf "$H"

begin_test "guard-reg: silent under a plugin runtime, whatever settings.json says"
# THE false-positive that matters: a plugin install registers from the plugin's
# own hooks.json and has no user settings.json entry. Warning there would hit
# exactly the users who are fully protected — the plugin/installer path
# divergence that has caused silent no-ops in this repo before.
H=$(_mkhome '{"hooks":{}}')
[ "$(_warns "$H" "/fake/plugin/root")" = "silent" ] && pass || fail "cried wolf under a plugin runtime"
rm -rf "$H"

begin_test "guard-reg: fails OPEN when settings.json is unreadable"
# An unreadable file is not evidence of a missing install.
H=$(_mkhome "")
[ "$(_warns "$H")" = "silent" ] && pass || fail "warned without evidence"
rm -rf "$H"

begin_test "guard-reg: kill switch disables it"
H=$(_mkhome '{"hooks":{}}')
OUT=$(printf '{}' | HOME="$H" SUPERCHARGER_GUARD_REG_CHECK=0 bash "$HOOK" 2>/dev/null)
[ -z "$OUT" ] && pass || fail "kill switch ignored"
rm -rf "$H"

begin_test "guard-reg: the warning is parseable systemMessage JSON"
# stderr from a hook lands in the debug log unhandled; stdout JSON is parsed and
# shown. A warning nobody sees is the very failure this hook reports.
H=$(_mkhome '{"hooks":{}}')
printf '{}' | HOME="$H" bash "$HOOK" 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert 'systemMessage' in d, d
assert 'NOT PROTECTING' in d['systemMessage']
" 2>/dev/null && pass || fail "output is not valid systemMessage JSON"
rm -rf "$H"

begin_test "guard-reg: registered on SessionStart in the generated artifact"
python3 - "$REPO_DIR" <<'PY' && pass || fail "not registered in hooks.json"
import json,sys,pathlib
d=json.loads((pathlib.Path(sys.argv[1])/"hooks/hooks.json").read_text())["hooks"]
ok=any('guard-registration-check' in h.get('command','')
       for g in d.get('SessionStart',[]) for h in g.get('hooks',[]))
sys.exit(0 if ok else 1)
PY

# --- PARTIAL loss (v4.0.1) ---------------------------------------------------
# The check fired only at exactly zero. Measured on 2026-08-30 against the live
# install: 1-of-154 registered was silent, and so was the real shape left behind
# by a /sc off + /sc on, where 59 of 154 came back as "matcher": null and the
# surviving 95 still carried the tag. Presence is a proxy; the defect is partial.

begin_test "guard-reg: warns when most registrations are GONE but some remain"
H=$(_mkhome "$(_settings_with 1)" 154)
[ "$(_warns "$H")" = "warns" ] && pass || fail "1 of 154 registrations did not warn"
rm -rf "$H"

begin_test "guard-reg: silent when the count matches the stamp"
H=$(_mkhome "$(_settings_with 154)" 154)
[ "$(_warns "$H")" = "silent" ] && pass || fail "false positive on a complete install"
rm -rf "$H"

begin_test "guard-reg: silent when MORE are registered than stamped"
# A user adding their own tagged hook, or an install that grew, must not warn.
H=$(_mkhome "$(_settings_with 160)" 154)
[ "$(_warns "$H")" = "silent" ] && pass || fail "cried wolf when registrations exceeded the stamp"
rm -rf "$H"

begin_test "guard-reg: fails OPEN when there is no stamp"
# Installs predating the stamp must keep the old presence behaviour, not warn.
H=$(_mkhome "$(_settings_with 1)")
[ "$(_warns "$H")" = "silent" ] && pass || fail "warned without a stamp to compare against"
rm -rf "$H"

begin_test "guard-reg: fails OPEN on a garbage or zero stamp"
H=$(_mkhome "$(_settings_with 1)" "abc"); R1=$(_warns "$H"); rm -rf "$H"
H=$(_mkhome "$(_settings_with 1)" 0);     R2=$(_warns "$H"); rm -rf "$H"
[ "$R1" = "silent" ] && [ "$R2" = "silent" ] && pass || fail "garbage=$R1 zero=$R2"

begin_test "guard-reg: the partial warning is parseable systemMessage JSON"
H=$(_mkhome "$(_settings_with 1)" 154)
OUT=$(printf '{}' | HOME="$H" bash "$HOOK" 2>/dev/null)
printf '%s' "$OUT" | python3 -c "
import json,sys
d=json.load(sys.stdin)
m=d['systemMessage']
assert 'PARTIAL' in m, m
assert '1 of 154' in m, m
" >/dev/null 2>&1 && pass || fail "unparseable or wrong partial warning: $OUT"
rm -rf "$H"

begin_test "guard-reg: install.sh stamps the count it registered"
# Without the stamp the comparison above can never run, and the check silently
# reverts to the presence proxy it had before.
grep -q 'registration-count' "$REPO_DIR/install.sh" \
  && grep -q "grep -o -- '$TAG'" "$REPO_DIR/install.sh" \
  && pass || fail "install.sh does not write .registration-count"

# --- v4.0.9: the stamp itself can be stripped ---------------------------------
#
# This check reads its baseline from a file nothing protects. Measured against
# the deployed harness-tamper-guard on 2026-09-01:
#     rm -f  ~/.claude/supercharger/.registration-count   allow
#     : >    ~/.claude/supercharger/.registration-count   allow
#     rm -rf ~/.claude/supercharger/hooks                 deny
# so removing the baseline silently disabled the check that notices missing
# registrations. Pattern named by PIsberg/vibetags' locked-files action: "a
# stripped lock is absent from the regenerated report and so invisible to any
# report-based check." The second signal is `.version`, written by the same
# install run.
#
# Both directions matter. Warning when the version says a stamp should exist is
# the fix; STAYING SILENT below the floor is what stops it crying wolf at the
# older installs this hook exists to serve.

_mkhome_ver() {  # $1 = settings body; $2 = version or "" ; $3 = stamp or ""
  local h; h=$(mktemp -d); mkdir -p "$h/.claude" "$h/.claude/supercharger"
  printf '%s\n' "$1" > "$h/.claude/settings.json"
  [ -n "${2:-}" ] && printf '%s\n' "$2" > "$h/.claude/supercharger/.version"
  [ -n "${3:-}" ] && printf '%s\n' "$3" > "$h/.claude/supercharger/.registration-count"
  printf '%s' "$h"
}

begin_test "guard-reg: a MISSING stamp warns when the version says it should exist"
H=$(_mkhome_ver "$(_settings_with 2)" "4.0.9" "")
[ "$(_warns "$H")" = "warns" ] && pass || fail "stamp stripped at 4.0.9 and the check went silent"
rm -rf "$H"

begin_test "guard-reg: the floor release itself warns"
H=$(_mkhome_ver "$(_settings_with 2)" "4.0.1" "")
[ "$(_warns "$H")" = "warns" ] && pass || fail "4.0.1 introduced the stamp; absence should warn"
rm -rf "$H"

begin_test "guard-reg: an install BELOW the floor stays silent (legitimately stampless)"
H=$(_mkhome_ver "$(_settings_with 2)" "4.0.0" "")
[ "$(_warns "$H")" = "silent" ] && pass || fail "cried wolf at a pre-stamp install"
rm -rf "$H"

begin_test "guard-reg: a much older install stays silent"
H=$(_mkhome_ver "$(_settings_with 2)" "2.29.41" "")
[ "$(_warns "$H")" = "silent" ] && pass || fail "cried wolf at 2.29.41"
rm -rf "$H"

begin_test "guard-reg: no version file means no verdict"
H=$(_mkhome_ver "$(_settings_with 2)" "" "")
[ "$(_warns "$H")" = "silent" ] && pass || fail "claimed a verdict with no second signal"
rm -rf "$H"

begin_test "guard-reg: an unparseable version means no verdict"
# Fail open on junk rather than guess — the same rule the stamp parser follows.
H=$(_mkhome_ver "$(_settings_with 2)" "not-a-version" "")
[ "$(_warns "$H")" = "silent" ] && pass || fail "claimed a verdict from an unparseable version"
rm -rf "$H"

begin_test "guard-reg: a present, satisfied stamp is still silent at 4.0.9"
# The regression this pairs with: the new branch must not fire when nothing is wrong.
H=$(_mkhome_ver "$(_settings_with 2)" "4.0.9" "2")
[ "$(_warns "$H")" = "silent" ] && pass || fail "new branch fires on a healthy install"
rm -rf "$H"

report
