#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

HOOK="$REPO_DIR/hooks/git-config-exec-guard.sh"
export SUPERCHARGER_HOME="$REPO_DIR"

echo "=== Git Config Exec Guard Tests ==="

TMP=$(mktemp -d)
mkin() { CMD="$2" SID="s$3" python3 - "$1" <<'PY'
import json, os, sys
open(sys.argv[1], "w").write(json.dumps({"tool_name": "Bash",
    "tool_input": {"command": os.environ["CMD"]}, "session_id": os.environ["SID"]}))
PY
}
verdict() {
  SUPERCHARGER_STATE="$(mktemp -d)" bash "$HOOK" < "$1" > "$TMP/o" 2>/dev/null
  python3 -c "import json;s=open('$TMP/o').read().strip();print(json.loads(s)['hookSpecificOutput']['permissionDecision'].upper() if s else 'ALLOW')"
}
n=0
check() { n=$((n+1)); mkin "$TMP/c$n.json" "$2" "$n"; begin_test "$1"; local g; g=$(verdict "$TMP/c$n.json"); [ "$g" = "$3" ] && pass || fail "expected $3 got $g — $2"; }

# --- DENY: always-executable keys with a command value ---
check "fsmonitor command"        "git config core.fsmonitor '!/tmp/x.sh'"          DENY
check "sshCommand sh -c"         "git config core.sshCommand 'sh -c id'"           DENY

# --- ASK: exec-capable key with a command-shaped value ---
check "credential.helper bang"   "git config credential.helper '!/tmp/h.sh'"       ASK
check "core.pager script"        "git config core.pager '!/tmp/x.sh'"              ASK
check "alias bang"               "git config alias.st '!/tmp/pwn.sh'"             ASK
check "persistent hooksPath"     "git config core.hooksPath /tmp/hooks"           ASK
check "filter clean cmd"         "git config filter.lfs.clean 'sh -c evil'"       ASK
check "editor node -e"           "git config core.editor 'node -e proc'"          ASK
check "difftool cmd"             "git config difftool.x.cmd 'sh -c d'"            ASK
check "sshCommand benign->ASK?"  "git config core.sshCommand 'ssh -i /k'"         ALLOW

# --- ALLOW: benign non-command values / non-exec keys ---
check "user.email"               "git config user.email me@x.com"                 ALLOW
check "pager less"               "git config core.pager less"                     ALLOW
check "credential.helper cache"  "git config credential.helper cache"             ALLOW
check "editor vim"               "git config core.editor vim"                     ALLOW
check "alias no bang"            "git config alias.co checkout"                   ALLOW
check "autocrlf"                 "git config core.autocrlf true"                  ALLOW
check "inline -c pager=less"     "git -c core.pager=less log"                     ALLOW
check "push.default"             "git config --global push.default simple"        ALLOW
check "editor code --wait"       "git config core.editor 'code --wait'"           ALLOW
check "not a git config"         "echo git config core.pager"                     ALLOW

# --- dedup, kill switch, fail-open ---
SS=$(mktemp -d); mkin "$TMP/dd.json" "git config core.pager '!/tmp/x.sh'" 98
begin_test "asks first, silent on repeat key (dedup)"
SUPERCHARGER_STATE="$SS" bash "$HOOK" < "$TMP/dd.json" >/dev/null 2>&1
second=$(SUPERCHARGER_STATE="$SS" bash "$HOOK" < "$TMP/dd.json" 2>/dev/null)
[ -z "$second" ] && pass || fail "expected SILENT on repeat: $second"
rm -rf "$SS"

begin_test "kill switch disables"
out=$(SUPERCHARGER_GIT_CONFIG_EXEC_GUARD=0 bash "$HOOK" < "$TMP/c1.json" 2>/dev/null)
[ -z "$out" ] && pass || fail "expected SILENT when disabled"

begin_test "malformed json fails open"
out=$(printf '%s' 'not json {' | bash "$HOOK" 2>/dev/null)
[ -z "$out" ] && pass || fail "expected fail-open silence"

rm -rf "$TMP"
report
