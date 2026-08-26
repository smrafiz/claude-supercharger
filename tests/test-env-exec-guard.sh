#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

HOOK="$REPO_DIR/hooks/env-exec-guard.sh"
export SUPERCHARGER_HOME="$REPO_DIR"

echo "=== Env Exec Guard Tests ==="

TMP=$(mktemp -d)
mkin() { CMD="$2" SID="s$3" python3 - "$1" <<'PY'
import json, os, sys
open(sys.argv[1], "w").write(json.dumps({"tool_name": "Bash",
    "tool_input": {"command": os.environ["CMD"]}, "session_id": os.environ["SID"]}))
PY
}
verdict() {
  SUPERCHARGER_STATE="$(mktemp -d)" bash "$HOOK" < "$1" > "$TMP/o" 2>/dev/null
  python3 -c "import json,sys;s=open(sys.argv[1]).read().strip();print('ASK' if s and json.loads(s)['hookSpecificOutput']['permissionDecision']=='ask' else 'ALLOW')" "$TMP/o"
}
n=0
check() { n=$((n+1)); mkin "$TMP/c$n" "$2" "$n"; begin_test "$1"; local g; g=$(verdict "$TMP/c$n"); [ "$g" = "$3" ] && pass || fail "expected $3 got $g — $2"; }

# --- should ASK: code-injecting env var ---
check "LD_PRELOAD"          'export LD_PRELOAD=/tmp/evil.so && git log'          ASK
check "LD_PRELOAD inline"   'LD_PRELOAD=/tmp/x.so git status'                    ASK
check "DYLD_INSERT_LIBS"    'export DYLD_INSERT_LIBRARIES=/tmp/l.dylib'          ASK
check "NODE_OPTIONS require" "NODE_OPTIONS='--require /tmp/x.js' npm test"       ASK
check "BASH_ENV any path"   'export BASH_ENV=/tmp/profile'                       ASK
check "ENV any path"        'export ENV=/tmp/x'                                  ASK
check "PYTHONSTARTUP"       'export PYTHONSTARTUP=~/.evil.py'                     ASK
check "GIT_SSH_COMMAND sh"  "export GIT_SSH_COMMAND='sh -c curl'"               ASK
check "PYTHONPATH tmp"      'export PYTHONPATH=/tmp:$P python x.py'               ASK
check "RUBYOPT -r<lib>"     'RUBYOPT=-rocra ruby app.rb'                         ASK
check "PERL5OPT -M<mod>"    'PERL5OPT=-Mevil perl x.pl'                          ASK
check "PROMPT_COMMAND pipe" 'export PROMPT_COMMAND="x|sh"'                       ASK

# --- should ALLOW: benign values / non-exec vars ---
check "NODE_OPTIONS heap"   'NODE_OPTIONS=--max-old-space-size=4096 npm run build' ALLOW
check "LD_LIBRARY_PATH sys" 'export LD_LIBRARY_PATH=/usr/local/lib'              ALLOW
check "PYTHONPATH opt"      'export PYTHONPATH=/opt/app/src'                     ALLOW
check "GIT_SSH_COMMAND ssh" 'export GIT_SSH_COMMAND="ssh -i ~/.ssh/id"'         ALLOW
check "PROMPT_COMMAND hist" 'export PROMPT_COMMAND="history -a"'                 ALLOW
check "EDITOR vim"          'export EDITOR=vim'                                  ALLOW
check "NODE_ENV prod"       'export NODE_ENV=production'                         ALLOW
check "plain command"       'git status && npm test'                            ALLOW

# --- dedup, kill, fail-open ---
SS=$(mktemp -d); mkin "$TMP/dd" 'export LD_PRELOAD=/tmp/x.so' 97
begin_test "asks first, silent on repeat var (dedup)"
SUPERCHARGER_STATE="$SS" bash "$HOOK" < "$TMP/dd" >/dev/null 2>&1
second=$(SUPERCHARGER_STATE="$SS" bash "$HOOK" < "$TMP/dd" 2>/dev/null)
[ -z "$second" ] && pass || fail "expected SILENT on repeat: $second"
rm -rf "$SS"

begin_test "kill switch disables"
out=$(SUPERCHARGER_ENV_EXEC_GUARD=0 bash "$HOOK" < "$TMP/c1" 2>/dev/null)
[ -z "$out" ] && pass || fail "expected SILENT when disabled"

begin_test "malformed json fails open"
out=$(printf '%s' 'not json {' | bash "$HOOK" 2>/dev/null)
[ -z "$out" ] && pass || fail "expected fail-open silence"

# --- v2.29.31: GIT_SSH_* names a PROGRAM, so the value is a command ----------
# These were already in the policy table under "shaped", which only fires on a value
# carrying $( , a pipe, a `sh -c`, or a script suffix. But `GIT_SSH_COMMAND=id git
# fetch` runs id with none of those present -- the variable names the executable, so
# any value is an invocation. The legitimate value is always some form of ssh, so
# that is now the test. From kenryu42/cc-safety-net's git.ssh-env rule.
check "git-ssh-bare-command"    "GIT_SSH_COMMAND=id git fetch origin"                    ASK
check "git-ssh-quoted-command"  "GIT_SSH_COMMAND='id' git fetch origin"                  ASK
check "git-ssh-abs-non-ssh"     "GIT_SSH_COMMAND=/tmp/payload git pull"                  ASK
check "git-ssh-env-prefix"      "env GIT_SSH_COMMAND=id git fetch"                       ASK
check "git-external-diff"       "GIT_EXTERNAL_DIFF=id git diff"                          ASK

# Precision: the real reason "shaped" was permissive -- these are how people
# legitimately use the variable, and they must not prompt.
check "git-ssh-with-identity"   "GIT_SSH_COMMAND='ssh -i ~/.ssh/id_ed25519' git fetch"   ALLOW
check "git-ssh-with-option"     "GIT_SSH_COMMAND='ssh -o StrictHostKeyChecking=no' git clone x" ALLOW
check "git-ssh-absolute-ssh"    "GIT_SSH_COMMAND=/usr/bin/ssh git pull"                  ALLOW
check "git-ssh-port-option"     "GIT_SSH_COMMAND='ssh -p 2222' git fetch"                ALLOW

rm -rf "$TMP"
report
