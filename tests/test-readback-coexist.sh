#!/usr/bin/env bash
# readback entries (tagged " #readback") share settings.json with ours. /sc off + /sc on,
# install (merge) and uninstall must never drop one, whatever group it sits in.
# Isolated HOME.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
TOGGLE="$REPO_DIR/tools/sc-toggle.sh"

echo "=== Readback Coexistence Tests ==="

# settings.json: readback + Supercharger groups with the SAME matchers (Stop: none,
# PreToolUse: Edit|MultiEdit|Write). MERGED=1 puts both tags in one group instead.
_setup() {
  setup_test_home
  mkdir -p "$HOME/.claude/supercharger/scope" "$HOME/.claude/supercharger/hooks" "$HOME/.claude/backups"
  cp "$REPO_DIR/hooks/lib-suppress.sh" "$REPO_DIR/hooks/lib-timing.sh" "$REPO_DIR/hooks/lib-paths.sh" \
     "$HOME/.claude/supercharger/hooks/" 2>/dev/null || true
  MERGED="${1:-0}" python3 - <<'PY'
import json, os
rb = lambda n: {"type": "command", "command": "bash rb/%s.sh || true #readback" % n}
sc = lambda n: {"type": "command", "command": "bash sc/%s.sh #supercharger" % n}
pre = "Edit|MultiEdit|Write"
if os.environ["MERGED"] == "1":
    hooks = {"Stop": [{"hooks": [rb("claim-check"), sc("stop-verify")]}],
             "PreToolUse": [{"matcher": pre, "hooks": [rb("test-guard"), sc("test-integrity-guard")]}]}
else:
    hooks = {"Stop": [{"hooks": [rb("claim-check")]}, {"hooks": [sc("stop-verify")]}],
             "PreToolUse": [{"matcher": pre, "hooks": [rb("test-guard")]},
                            {"matcher": pre, "hooks": [sc("test-integrity-guard")]}]}
json.dump({"hooks": hooks}, open(os.environ["HOME"] + "/.claude/settings.json", "w"), indent=2)
PY
}
# _n TAG : hooks carrying TAG;  _mixed : groups holding both tags
_n() {
  TAG="$1" python3 -c '
import json, os
s = json.load(open(os.environ["HOME"] + "/.claude/settings.json"))
print(sum(1 for v in s.get("hooks", {}).values() for e in v for h in e["hooks"] if os.environ["TAG"] in h.get("command", "")))'
}
_mixed() {
  python3 -c '
import json, os
s = json.load(open(os.environ["HOME"] + "/.claude/settings.json"))
print(sum(1 for v in s.get("hooks", {}).values() for e in v
  if any("#readback" in h["command"] for h in e["hooks"]) and any("#supercharger" in h["command"] for h in e["hooks"])))'
}
_lib() { ( . "$REPO_DIR/lib/hooks.sh"; "$@" ) >/dev/null 2>&1; }

begin_test "/sc off then on: readback kept, ours restored, never in one group"
_setup
bash "$TOGGLE" off >/dev/null 2>&1
off_rb=$(_n '#readback'); off_sc=$(_n '#supercharger')
bash "$TOGGLE" on >/dev/null 2>&1
[ "$off_rb" = 2 ] && [ "$off_sc" = 0 ] && [ "$(_n '#readback')" = 2 ] && [ "$(_n '#supercharger')" = 2 ] \
  && [ "$(_mixed)" = 0 ] && pass || fail "off rb=$off_rb sc=$off_sc; now rb=$(_n '#readback') sc=$(_n '#supercharger') mixed=$(_mixed)"
teardown_test_home

begin_test "/sc off, on, then uninstall strip: readback survives, ours gone"
_setup
bash "$TOGGLE" off >/dev/null 2>&1; bash "$TOGGLE" on >/dev/null 2>&1
_lib remove_supercharger_hooks
[ "$(_n '#readback')" = 2 ] && [ "$(_n '#supercharger')" = 0 ] && pass \
  || fail "rb=$(_n '#readback') sc=$(_n '#supercharger')"
teardown_test_home

begin_test "/sc off, on, then reinstall (merge): readback survives, ours present"
_setup
bash "$TOGGLE" off >/dev/null 2>&1; bash "$TOGGLE" on >/dev/null 2>&1
_lib merge_hooks_into_settings full true
[ "$(_n '#readback')" = 2 ] && [ "$(_n '#supercharger')" -gt 2 ] && pass \
  || fail "rb=$(_n '#readback') sc=$(_n '#supercharger')"
teardown_test_home

begin_test "uninstall strip on a group that already mixes both tags keeps the readback hook"
_setup 1
_lib remove_supercharger_hooks
[ "$(_n '#readback')" = 2 ] && [ "$(_n '#supercharger')" = 0 ] && pass \
  || fail "rb=$(_n '#readback') sc=$(_n '#supercharger')"
teardown_test_home

begin_test "reinstall merge on a group that already mixes both tags keeps the readback hook"
_setup 1
_lib merge_hooks_into_settings full true
[ "$(_n '#readback')" = 2 ] && [ "$(_mixed)" = 0 ] && pass \
  || fail "rb=$(_n '#readback') mixed=$(_mixed)"
teardown_test_home

begin_test "/sc off on a mixed group keeps the readback hook, on restores ours"
_setup 1
bash "$TOGGLE" off >/dev/null 2>&1
off_rb=$(_n '#readback'); off_sc=$(_n '#supercharger')
bash "$TOGGLE" on >/dev/null 2>&1
[ "$off_rb" = 2 ] && [ "$off_sc" = 0 ] && [ "$(_n '#readback')" = 2 ] && [ "$(_n '#supercharger')" = 2 ] && pass \
  || fail "off rb=$off_rb sc=$off_sc; now rb=$(_n '#readback') sc=$(_n '#supercharger')"
teardown_test_home

report
