#!/usr/bin/env bash
# guard-drift-alarm: at session start, name every registered Supercharger guard
# whose script is missing or not executable. Claude Code treats both as a
# non-blocking error and lets the call through, so silence here was the bug: eight
# guards ran nowhere on the plugin for three months.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

HOOK="$REPO_DIR/hooks/guard-drift-alarm.sh"
TD=$(mktemp -d); trap 'rm -rf "$TD"' EXIT
H="$TD/supercharger/hooks"; mkdir -p "$H"
printf '#!/bin/sh\nexit 0\n' > "$H/ok-guard.sh"; chmod 755 "$H/ok-guard.sh"
printf '#!/bin/sh\nexit 0\n' > "$H/noexec-guard.sh"; chmod 644 "$H/noexec-guard.sh"

settings() { # commands... -> settings path
  local f="$TD/s-$RANDOM.json"
  python3 -c '
import json, sys
print(json.dumps({"hooks": {"PreToolUse": [{"matcher": "Bash", "hooks": [
  {"type": "command", "command": c} for c in sys.argv[1:]]}]}}))' "$@" > "$f"
  printf '%s' "$f"
}
alarm() { SUPERCHARGER_DRIFT_SETTINGS="$1" CLAUDE_PLUGIN_ROOT="${2:-}" bash "$HOOK" </dev/null 2>/dev/null; }

echo "=== Guard Drift Alarm Tests ==="

begin_test "drift: silent when every guard can run"
OUT=$(alarm "$(settings "$H/ok-guard.sh #supercharger")")
[ -z "$OUT" ] && pass || fail "expected silence: $OUT"

begin_test "GAP CHECK: names a guard without +x"
OUT=$(alarm "$(settings "$H/ok-guard.sh #supercharger" "$H/noexec-guard.sh #supercharger")")
printf '%s' "$OUT" | grep -q 'noexec-guard.sh (not executable)' && ! printf '%s' "$OUT" | grep -q 'ok-guard' \
  && pass || fail "got: $OUT"

begin_test "GAP CHECK: names a registered guard whose file is gone"
OUT=$(alarm "$(settings "$H/gone-guard.sh #supercharger")")
printf '%s' "$OUT" | grep -q 'gone-guard.sh (missing)' && pass || fail "got: $OUT"

begin_test "drift: a script run through bash needs no +x"
OUT=$(alarm "$(settings "bash $H/noexec-guard.sh #supercharger")")
[ -z "$OUT" ] && pass || fail "false alarm: $OUT"

begin_test "drift: another tool's broken hook is not reported"
OUT=$(alarm "$(settings "/opt/other-tool/hook.sh")")
[ -z "$OUT" ] && pass || fail "false alarm: $OUT"

begin_test "GAP CHECK: plugin runtime checks the plugin's hooks.json"
P="$TD/plugin"; mkdir -p "$P/hooks"; cp "$H/noexec-guard.sh" "$P/hooks/"; chmod 644 "$P/hooks/noexec-guard.sh"
printf '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"\\"${CLAUDE_PLUGIN_ROOT}\\"/hooks/noexec-guard.sh"}]}]}}' > "$P/hooks/hooks.json"
OUT=$(alarm "$TD/none.json" "$P")
printf '%s' "$OUT" | grep -q 'noexec-guard.sh (not executable)' && pass || fail "got: $OUT"

begin_test "drift: output is valid hook JSON carrying a systemMessage"
OUT=$(alarm "$(settings "$H/gone-guard.sh #supercharger")")
printf '%s' "$OUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["systemMessage"].startswith("[GUARDS]")' \
  && pass || fail "bad JSON: $OUT"

begin_test "drift: registered on SessionStart in the plugin hooks.json"
jq -e '[.hooks.SessionStart[].hooks[].command|select(test("guard-drift-alarm"))]|length==1' "$REPO_DIR/hooks/hooks.json" >/dev/null \
  && pass || fail "not registered"

for mode in full standard; do
  begin_test "drift: the installer registers it on SessionStart ($mode)"
  setup_test_home >/dev/null 2>&1; mkdir -p "$HOME/.claude"; echo '{}' > "$HOME/.claude/settings.json"
  ( source "$REPO_DIR/lib/hooks.sh"; merge_hooks_into_settings "$mode" "true" ) >/dev/null 2>&1
  N=$(jq '[.hooks.SessionStart[]?.hooks[].command|select(test("guard-drift-alarm"))]|length' "$HOME/.claude/settings.json" 2>/dev/null)
  teardown_test_home >/dev/null 2>&1
  [ "$N" = 1 ] && pass || fail "registered $N times in $mode"
done

begin_test "drift: SUPERCHARGER_DRIFT_ALARM=0 silences it"
OUT=$(SUPERCHARGER_DRIFT_ALARM=0 SUPERCHARGER_DRIFT_SETTINGS="$(settings "$H/gone-guard.sh #supercharger")" bash "$HOOK" </dev/null 2>/dev/null)
[ -z "$OUT" ] && pass || fail "not silenced: $OUT"

report
