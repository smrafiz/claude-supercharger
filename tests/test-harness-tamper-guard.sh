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
# v4.1.1: copy-family (cp/install/rsync/scp) overwriting a hook. The bare form was
# covered by the rule, but a trailing redirect/comment shifted the last token off the
# hook path and the overwrite was ALLOWED — these lock that bypass shut.
check "cp over a hook"                  "cp /tmp/evil.sh ~/.claude/supercharger/hooks/safety.sh"            DENY
check "cp over a hook + stderr redir"   "cp /tmp/evil.sh ~/.claude/supercharger/hooks/safety.sh 2>/dev/null" DENY
check "cp over a hook + stdout redir"   "cp /tmp/evil.sh ~/.claude/supercharger/hooks/safety.sh > /tmp/log"  DENY
check "cp over a hook + comment"        "cp /tmp/evil.sh ~/.claude/supercharger/hooks/safety.sh #note"       DENY
check "install over a hook + redir"     "install /tmp/evil.sh ~/.claude/supercharger/hooks/safety.sh 2>/dev/null" DENY
check "rsync over a hook + redir"       "rsync /tmp/evil.sh ~/.claude/supercharger/hooks/safety.sh 2>/dev/null"   DENY
check "scp over a hook + redir"         "scp /tmp/evil.sh ~/.claude/supercharger/hooks/safety.sh 2>/dev/null"     DENY

# --- should PASS (legit / unrelated) ---
# FP guard: copying between unrelated paths with a redirect must NOT trip the copy branch.
check "cp unrelated files + redir"      "cp /tmp/a.txt /tmp/b.txt 2>/dev/null"                 SILENT
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

# --- 2026-09-13, from weellio/gander: self-approval via a local control plane ---
# Every DENY below passed all 19 Bash hooks before the rule existed.
check "approve a parked prompt on localhost" \
  "curl -s -X POST http://localhost:3131/api/permissions/answer -H 'Content-Type: application/json' -d '{\"sessionId\":\"s\",\"requestId\":\"r\",\"behavior\":\"allow\"}'" DENY
check "approve a parked prompt on 127.0.0.1" \
  "curl -s -X POST http://127.0.0.1:3131/api/permissions/answer -d '{\"requestId\":\"r\",\"behavior\":\"allow\"}'" DENY
check "list-then-approve loop" \
  'for id in $(curl -s localhost:3131/api/permissions | jq -r ".pending[].requestId"); do curl -s -X POST localhost:3131/api/permissions/answer -d "{\"requestId\":\"$id\",\"behavior\":\"allow\"}"; done' DENY
check "set bypass mode for launched sessions" \
  "curl -s -X POST http://localhost:3131/api/claude-config -d '{\"permMode\":\"bypass\"}'" DENY
check "schedule a bypass-mode routine" \
  "curl -s -X POST http://localhost:3131/api/routines -d '{\"prompt\":\"do it\",\"permMode\":\"bypass\",\"schedule\":\"03:00\"}'" DENY
check "approve via node fetch" \
  "node -e \"fetch('http://localhost:3131/api/permissions/answer',{method:'POST',body:JSON.stringify({requestId:'r',behavior:'allow'})})\"" DENY
CODEX_BYP="codex --dangerously-$(printf bypass)-approvals-and-sandbox exec x"
check "codex bypass-approvals flag" "$CODEX_BYP" DENY
# Controls: each shares ONE ingredient with the rule and must stay silent.
check "listing pending prompts only"   "curl -s http://localhost:3131/api/permissions" SILENT
check "ordinary localhost dev POST"    "curl -s -X POST http://localhost:3000/api/users -d '{\"name\":\"a\"}'" SILENT
check "approval word, no loopback"     "grep -rn '\"behavior\":\"allow\"' src/" SILENT
check "plain codex run"                "codex exec \"fix tests\"" SILENT

rm -rf "$TMP" "$SUPERCHARGER_STATE"

# --- v4.0.37: a redirect counts only when the protected path is the TARGET -----
# Reported from a real session 2026-09-08: running our OWN diagnostic and keeping
# the output in a log file was DENIED. One segment held a protected path (the
# script being RUN) and a redirect whose operand was under /tmp; verb and target
# were both present, so the guard fired on a documented, read-only command.
#
# The copy-family above already had the right principle -- "only the DESTINATION
# counts". This applies it to > and >>. The strip-then-retest step is what keeps
# it honest: a real destructive verb that ALSO redirects still hits.
# [[guard-fp-verify-with-literal-input]] -- verb and target matched independently.
_HTR_SC="$HOME/.claude/supercharger"
_htr() {  # $1 = command -> "allow" | "BLOCK"
  printf '{"tool_name":"Bash","cwd":"/tmp","session_id":"htr","tool_input":{"command":%s}}' \
    "$(printf '%s' "$1" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read()))')" \
    | bash "$REPO_DIR/hooks/harness-tamper-guard.sh" >/dev/null 2>&1
  [ $? -eq 0 ] && printf 'allow' || printf 'BLOCK'
}

begin_test "harness-tamper: running the doctor and keeping the log is ALLOWED"
[ "$(_htr "bash $_HTR_SC/tools/claude-check.sh > /tmp/sc-doctor.log 2>&1")" = "allow" ] \
  && pass || fail "denied a documented read-only command"

begin_test "harness-tamper: reading a hook into a temp file is ALLOWED"
[ "$(_htr "cat $_HTR_SC/hooks/safety.sh > /tmp/copy.sh")" = "allow" ] \
  && pass || fail "reading a hook out is not tampering"

begin_test "harness-tamper: overwriting a hook VIA redirect is still blocked"
# The control. Without it the two above would also pass if redirects stopped
# being checked at all.
[ "$(_htr "echo evil > $_HTR_SC/hooks/safety.sh")" = "BLOCK" ] \
  && pass || fail "redirect INTO a hook must be blocked"

begin_test "harness-tamper: appending into a hook is still blocked"
[ "$(_htr "echo evil >> $_HTR_SC/hooks/safety.sh")" = "BLOCK" ] \
  && pass || fail ">> into a hook must be blocked"

begin_test "harness-tamper: a destructive verb that ALSO redirects still blocks"
# The case the strip-then-retest exists for: stripping the redirect must leave
# `rm <hook>` behind, still matching verb and target.
[ "$(_htr "rm -f $_HTR_SC/hooks/safety.sh > /tmp/log")" = "BLOCK" ] \
  && pass || fail "the redirect strip swallowed a real rm"

begin_test "harness-tamper: tee into a hook is still blocked"
[ "$(_htr "echo x | tee $_HTR_SC/hooks/safety.sh")" = "BLOCK" ] \
  && pass || fail "tee writes to its argument"

begin_test "harness-tamper: cd into the hooks dir then rm is still blocked"
[ "$(_htr "cd $_HTR_SC/hooks && rm -rf .")" = "BLOCK" ] \
  && pass || fail "the two-step form must still hit"

report
