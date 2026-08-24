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

_mkhome() {  # $1 = settings body, or "" for no file
  local h; h=$(mktemp -d); mkdir -p "$h/.claude"
  [ -n "$1" ] && printf '%s\n' "$1" > "$h/.claude/settings.json"
  printf '%s' "$h"
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

report
