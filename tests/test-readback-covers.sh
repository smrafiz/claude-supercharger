#!/usr/bin/env bash
# readback covers file: project-config.sh writes ~/.claude/readback-covers/<sid> listing
# the guards still active for the project; sc-toggle empties it. Isolated HOME + state.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
PC="$REPO_DIR/hooks/project-config.sh"
ALL=$'test-integrity-guard\ntest-mask-guard\nclaim-evidence-gate\nfailure-tracker'

echo "=== Readback Covers Tests ==="

# fresh HOME with all four guards registered; P = project dir (READBACK.md unless arg 0)
_setup() {
  setup_test_home
  export SUPERCHARGER_STATE="$HOME/state"; mkdir -p "$SUPERCHARGER_STATE/scope"
  unset CLAUDE_PLUGIN_ROOT CLAUDE_PLUGIN_DATA SUPERCHARGER_PROFILE CLAUDE_CODE_SESSION_ID
  unset SUPERCHARGER_TEST_INTEGRITY_GUARD SUPERCHARGER_TEST_MASK_GUARD SUPERCHARGER_CLAIM_EVIDENCE_GATE
  python3 - <<'PY'
import json, os
h = os.environ["HOME"]
names = ["test-integrity-guard", "test-mask-guard", "claim-evidence-gate", "failure-tracker"]
s = {"hooks": {"PreToolUse": [{"hooks": [{"type": "command",
     "command": "bash %s/.claude/supercharger/hooks/%s.sh #supercharger" % (h, n)}]} for n in names]}}
json.dump(s, open(h + "/.claude/settings.json", "w"), indent=2)
PY
  P="$HOME/proj"; mkdir -p "$P"; : > "$P/READBACK.md"
  export CLAUDE_PROJECT_DIR="$P"
}
# run SID [TRANSCRIPT_ID]
_run() {
  local tp=""; [ -n "${2:-}" ] && tp="$HOME/$2.jsonl"
  printf '{"session_id":"%s","cwd":"%s","transcript_path":"%s"}' "$1" "$P" "$tp" | bash "$PC" >/dev/null 2>&1
}
_covers() { cat "$HOME/.claude/readback-covers/$1" 2>/dev/null; }

begin_test "all four active -> all four listed"
_setup; _run s1
[ "$(_covers s1)" = "$ALL" ] && pass || fail "got [$(_covers s1)]"; teardown_test_home

begin_test "no READBACK.md -> no covers dir"
_setup; rm "$P/READBACK.md"; _run s1
[ ! -e "$HOME/.claude/readback-covers" ] && pass || fail "dir exists"; teardown_test_home

begin_test "env toggles drop only their guard"
_setup; SUPERCHARGER_TEST_MASK_GUARD=0 SUPERCHARGER_CLAIM_EVIDENCE_GATE=0 _run s1
[ "$(_covers s1)" = $'test-integrity-guard\nfailure-tracker' ] && pass || fail "got [$(_covers s1)]"; teardown_test_home

begin_test ".supercharger.json disableHooks drops that guard (not claim-evidence-gate's env-only path)"
_setup; echo '{"disableHooks":["failure-tracker","test-integrity-guard"]}' > "$P/.supercharger.json"; _run s1
[ "$(_covers s1)" = $'test-mask-guard\nclaim-evidence-gate' ] && pass || fail "got [$(_covers s1)]"; teardown_test_home

begin_test "profile minimal drops failure-tracker"
_setup; echo '{"profile":"minimal"}' > "$P/.supercharger.json"; _run s1
[ "$(_covers s1)" = $'test-integrity-guard\ntest-mask-guard\nclaim-evidence-gate' ] && pass || fail "got [$(_covers s1)]"; teardown_test_home

begin_test "hook commented out by hook-toggle -> not listed; absent from settings -> not listed"
_setup
sed -i.bak 's|"command": "bash \(.*/test-mask-guard.sh\)|"command": "# bash \1|; /claude-evidence-gate/d' "$HOME/.claude/settings.json"
python3 - <<'PY'
import json, os
p = os.environ["HOME"] + "/.claude/settings.json"; s = json.load(open(p))
s["hooks"]["PreToolUse"] = [e for e in s["hooks"]["PreToolUse"] if "claim-evidence-gate" not in e["hooks"][0]["command"]]
json.dump(s, open(p, "w"), indent=2)
PY
_run s1
[ "$(_covers s1)" = $'test-integrity-guard\nfailure-tracker' ] && pass || fail "got [$(_covers s1)]"; teardown_test_home

begin_test "plugin runtime counts as registered"
_setup; rm "$HOME/.claude/settings.json"; CLAUDE_PLUGIN_ROOT="$REPO_DIR" _run s1
[ "$(_covers s1)" = "$ALL" ] && pass || fail "got [$(_covers s1)]"; teardown_test_home

begin_test "disableAllHooks -> empty file"
_setup; mkdir -p "$P/.claude"; echo '{"disableAllHooks": true}' > "$P/.claude/settings.local.json"; _run s1
[ -f "$HOME/.claude/readback-covers/s1" ] && [ ! -s "$HOME/.claude/readback-covers/s1" ] && pass || fail "got [$(_covers s1)]"; teardown_test_home

begin_test "sid is sanitised; resume writes payload and transcript ids"
_setup; _run 'a/../b' tid-9
[ -f "$HOME/.claude/readback-covers/ab" ] && [ -f "$HOME/.claude/readback-covers/tid-9" ] \
  && [ "$(ls "$HOME/.claude/readback-covers" | wc -l | tr -d ' ')" = 2 ] && pass || fail "$(ls -A "$HOME/.claude/readback-covers")"; teardown_test_home

begin_test "files older than 7 days are pruned, fresh ones kept"
_setup; mkdir -p "$HOME/.claude/readback-covers"; : > "$HOME/.claude/readback-covers/old"
touch -t 200001010000 "$HOME/.claude/readback-covers/old"; _run s1
[ ! -e "$HOME/.claude/readback-covers/old" ] && [ -f "$HOME/.claude/readback-covers/s1" ] && pass || fail "$(ls -A "$HOME/.claude/readback-covers")"; teardown_test_home

begin_test "/sc off and /sc on empty existing covers files"
_setup; mkdir -p "$HOME/.claude/supercharger/scope" "$HOME/.claude/backups"; _run s1
SUPERCHARGER_STATE="$HOME/.claude/supercharger"
bash "$REPO_DIR/tools/sc-toggle.sh" off >/dev/null 2>&1
a=$([ -f "$HOME/.claude/readback-covers/s1" ] && [ ! -s "$HOME/.claude/readback-covers/s1" ] && echo y)
printf 'x\n' > "$HOME/.claude/readback-covers/s1"
bash "$REPO_DIR/tools/sc-toggle.sh" on >/dev/null 2>&1
b=$([ -f "$HOME/.claude/readback-covers/s1" ] && [ ! -s "$HOME/.claude/readback-covers/s1" ] && echo y)
[ "$a$b" = yy ] && pass || fail "off=[$a] on=[$b]"; teardown_test_home

begin_test "syntax: bash -n lib-readback-covers.sh"
bash -n "$REPO_DIR/hooks/lib-readback-covers.sh" && pass || fail "syntax"

report
