#!/usr/bin/env bash
# guard-canary must FAIL on an inert guard. A canary that passes with the defect
# present is the presence check it replaces, so the negative cases are the point.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
H="$REPO_DIR/hooks"

settings() { # bash_matcher, write_matcher, safety_cmd -> settings file path
  local f="$TMP/s-$RANDOM.json"
  BM="$1" WM="$2" SC="$3" H="$H" python3 -c '
import json, os
h = os.environ["H"]
print(json.dumps({"hooks": {"PreToolUse": [
  {"matcher": os.environ["BM"], "hooks": [{"type": "command", "command": os.environ["SC"]},
                                           {"type": "command", "command": h + "/git-safety.sh"},
                                           {"type": "command", "command": h + "/harness-tamper-guard.sh"}]},
  {"matcher": os.environ["WM"], "hooks": [{"type": "command", "command": h + "/path-guard.sh"}]}]}}))' > "$f"
  printf '%s' "$f"
}
canary() { bash "$REPO_DIR/tools/guard-canary.sh" --settings "$1" 2>&1; }

echo "=== Guard Canary Tests ==="

begin_test "every core guard stops its canary when wired correctly"
OUT=$(canary "$(settings 'Bash|Monitor' 'Write|Edit' "$H/safety.sh #supercharger")"); RC=$?
[ "$RC" -eq 0 ] && [ "$(printf '%s' "$OUT" | grep -c '✓')" -eq 4 ] && pass || fail "rc=$RC: $OUT"

begin_test "GAP CHECK: a matcher that no longer selects the tool fails"
# Matchers are anchored: 'Bas' selects nothing (the v2.24.5 mcp__ class).
OUT=$(canary "$(settings 'Bas' 'Write|Edit' "$H/safety.sh")"); RC=$?
[ "$RC" -eq 1 ] && printf '%s' "$OUT" | grep -q 'safety.sh: registered, but its matcher does not select Bash' && pass || fail "rc=$RC: $OUT"

begin_test "GAP CHECK: a registration pointing at a hook that lets everything through fails"
OUT=$(canary "$(settings 'Bash' 'Write|Edit' "true /x/safety.sh")"); RC=$?
[ "$RC" -eq 1 ] && printf '%s' "$OUT" | grep -q 'safety.sh: let it through' && pass || fail "rc=$RC: $OUT"

begin_test "GAP CHECK: a guard missing from settings fails"
OUT=$(canary "$(settings 'Bash' 'Read' "$H/safety.sh")"); RC=$?
[ "$RC" -eq 1 ] && printf '%s' "$OUT" | grep -q 'path-guard.sh: registered, but its matcher does not select Write' && pass || fail "rc=$RC: $OUT"

begin_test "canary calls do not reach the real block ledger"
LEDGER_HOME="$TMP/home"; mkdir -p "$LEDGER_HOME/.claude/supercharger/scope"
HOME="$LEDGER_HOME" bash "$REPO_DIR/tools/guard-canary.sh" --settings "$(settings 'Bash' 'Write' "$H/safety.sh")" >/dev/null 2>&1
[ ! -s "$LEDGER_HOME/.claude/supercharger/scope/.blocked-commands" ] && pass || fail "ledger written: $(cat "$LEDGER_HOME/.claude/supercharger/scope/.blocked-commands")"

# Liveness: a registered hook that cannot run is a non-blocking error in Claude Code,
# so the call goes ahead unguarded. Eight guards were committed without +x and never
# ran on the plugin (2026-07-19 to 2026-10-19).
live() { # extra hook command -> canary output; settings carry the four core guards plus it
  local f
  f=$(settings 'Bash' 'Write|Edit' "$H/safety.sh")
  EXTRA="$1" python3 -c '
import json, os, sys
d = json.load(open(sys.argv[1]))
d["hooks"]["PreToolUse"].append({"matcher": "Bash", "hooks": [{"type": "command", "command": os.environ["EXTRA"]}]})
json.dump(d, open(sys.argv[1], "w"))' "$f"
  canary "$f"
}
LD="$TMP/supercharger/hooks"; mkdir -p "$LD"
printf '#!/bin/sh\nexit 0\n' > "$LD/bulk-exfil-guard.sh"  # a stub: liveness is about running, not denying

begin_test "liveness: a runnable extra guard passes"
chmod 755 "$LD/bulk-exfil-guard.sh"
OUT=$(live "$LD/bulk-exfil-guard.sh"); RC=$?
[ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -q 'all 1 other PreToolUse hooks run' && pass || fail "rc=$RC: $OUT"

begin_test "GAP CHECK: liveness fails a guard without +x"
chmod 644 "$LD/bulk-exfil-guard.sh"
OUT=$(live "$LD/bulk-exfil-guard.sh"); RC=$?
[ "$RC" -eq 1 ] && printf '%s' "$OUT" | grep -q 'bulk-exfil-guard.sh does not run on a Bash call (not executable)' && pass || fail "rc=$RC: $OUT"

begin_test "GAP CHECK: liveness fails a registered guard whose file is gone"
OUT=$(live "$LD/gone-guard.sh"); RC=$?
[ "$RC" -eq 1 ] && printf '%s' "$OUT" | grep -q 'gone-guard.sh does not run on a Bash call (not found)' && pass || fail "rc=$RC: $OUT"

begin_test "liveness: another tool's broken hook is not scored"
OUT=$(live "/opt/other-tool/hook.sh"); RC=$?
[ "$RC" -eq 0 ] && pass || fail "rc=$RC: $OUT"

report
