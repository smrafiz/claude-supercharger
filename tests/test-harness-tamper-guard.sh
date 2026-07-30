#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

HOOK="$REPO_DIR/hooks/harness-tamper-guard.sh"
export SUPERCHARGER_HOME="$REPO_DIR"
SUPERCHARGER_STATE="$(mktemp -d)"; export SUPERCHARGER_STATE   # keep the block-ledger write off the real state

echo "=== Harness Tamper Guard Tests ==="

TMP=$(mktemp -d)
mkcmd() { CMD="$2" python3 - "$1" <<'PY'
import json, os, sys
open(sys.argv[1], "w").write(json.dumps({"tool_name": "Bash", "tool_input": {"command": os.environ["CMD"]}, "cwd": "/x"}))
PY
}
verdict() { bash "$HOOK" < "$1" 2>/dev/null | python3 -c '
import sys, json
s = sys.stdin.read().strip()
print("SILENT" if not s else json.loads(s).get("hookSpecificOutput", {}).get("permissionDecision", "?").upper())'
}
# Assemble the flag from fragments so the verbatim token never sits in this file.
SKIP="claude --dangerously-$(printf skip)-permissions"
BYP="claude --permission-mode bypassPermissions"

check() { # name  command  expected
  mkcmd "$TMP/$1.json" "$2"
  begin_test "$1"
  local got; got=$(verdict "$TMP/$1.json")
  [ "$got" = "$3" ] && pass || fail "expected $3, got $got — cmd: $2"
}

# --- should DENY ---
check "skip-permissions flag"          "$SKIP"                                                 DENY
check "bypassPermissions mode"         "$BYP"                                                  DENY
check "rm a hook script"               "rm ~/.claude/supercharger/hooks/safety.sh"            DENY
check "chmod -x the hooks dir"         "chmod -x ~/.claude/supercharger/hooks/foo.sh"         DENY
check "mv a hook away"                 "mv ~/.claude/supercharger/hooks/safety.sh /tmp/x"     DENY
check "truncate a hook"               "truncate -s0 ~/.claude/supercharger/hooks/safety.sh"   DENY
check "touch the kill-switch file"     "touch ~/.claude/supercharger/scope/.supercharger-disabled" DENY
check "rm plugin hooks dir"            "rm -rf ~/.claude/plugins/data/x/hooks/"               DENY
check "redirect over a hook"           "echo x > ~/.claude/supercharger/hooks/safety.sh"      DENY

# --- should PASS (legit / unrelated) ---
check "update.sh runs"                 "bash ~/.claude/supercharger/tools/update.sh --yes"    SILENT
# v2.26.1: `sc-toggle off` now raises a CONFIRM rather than passing silently. It sets
# the kill-switch, after which every hook exits 0 — one command retires every other
# guard, which is the first step a prompt injection would want. It stays permitted
# (ASK, not DENY) because /sc off is a documented user control; what changed is that it
# can no longer happen unseen. See tests/test-selfdisable-confirm.sh for the full
# contract, including that autopilot cannot swallow the confirm.
check "sc-toggle off asks for confirmation" "bash ~/.claude/supercharger/tools/sc-toggle.sh off" ASK
check "sc-toggle on runs"              "bash ~/.claude/supercharger/tools/sc-toggle.sh on"    SILENT
check "repo-relative dev chmod"        "chmod +x hooks/foo.sh"                                SILENT
check "listing the hooks dir"          "ls ~/.claude/supercharger/hooks/"                     SILENT
check "reading a hook"                 "cat ~/.claude/supercharger/hooks/safety.sh"           SILENT
check "ordinary command"               "git status"                                           SILENT

# --- kill switch + fail-open ---
begin_test "kill switch SUPERCHARGER_HARNESS_TAMPER_GUARD=0 suppresses"
mkcmd "$TMP/ks.json" "rm ~/.claude/supercharger/hooks/safety.sh"
OUT=$(SUPERCHARGER_HARNESS_TAMPER_GUARD=0 bash "$HOOK" < "$TMP/ks.json" 2>/dev/null)
[ -z "$OUT" ] && pass || fail "kill switch should suppress"

begin_test "fail-open on malformed input"
printf 'not json' > "$TMP/bad.json"
OUT=$(bash "$HOOK" < "$TMP/bad.json" 2>/dev/null); RC=$?
[ -z "$OUT" ] && [ "$RC" -eq 0 ] && pass || fail "should fail-open silently (rc=$RC)"

# v2.23.10: a benign command whose CWD merely contains "supercharger" (this repo,
# the install dir) must stay silent — the fast-path token was tightened off the
# bare substring so it no longer over-processes there.
begin_test "benign command in a supercharger-named cwd stays silent"
printf '{"tool_name":"Bash","tool_input":{"command":"echo hi"},"cwd":"/Users/x/claude-supercharger"}' > "$TMP/scwd.json"
OUT=$(bash "$HOOK" < "$TMP/scwd.json" 2>/dev/null)
[ -z "$OUT" ] && pass || fail "benign cmd in supercharger cwd wrongly flagged: $OUT"

# v2.23.26: inline-config flag smuggling + the --allow- skip-perms variant.
check "allow-dangerously-skip-permissions variant" "claude --allow-dangerously-skip-permissions -p x" DENY
check "inline --settings JSON to claude"           'claude --settings {"hooks":{"PreToolUse":[]}} -p x' DENY
check "inline --mcp-config JSON to claude"          'claude --mcp-config {"mcpServers":{}} -p x'          DENY

begin_test "settings FILE path (not inline) stays silent"
mkcmd "$TMP/sfile.json" "claude --settings ./my-settings.json -p x"
[ "$(verdict "$TMP/sfile.json")" = "SILENT" ] && pass || fail "settings file path wrongly flagged"

begin_test "mcp-config FILE (not inline) stays silent"
mkcmd "$TMP/mfile.json" "claude --mcp-config config.json -p x"
[ "$(verdict "$TMP/mfile.json")" = "SILENT" ] && pass || fail "mcp-config file wrongly flagged"

begin_test "--settings to a non-claude tool stays silent"
mkcmd "$TMP/other.json" "eslint --settings foo.json"
[ "$(verdict "$TMP/other.json")" = "SILENT" ] && pass || fail "non-claude --settings wrongly flagged"

rm -rf "$TMP" "$SUPERCHARGER_STATE"
report
