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
  python3 -c "import json,sys;s=open(sys.argv[1]).read().strip();print(json.loads(s)['hookSpecificOutput']['permissionDecision'].upper() if s else 'ALLOW')" "$TMP/o"
}
n=0
check() { n=$((n+1)); mkin "$TMP/c$n.json" "$2" "$n"; begin_test "$1"; local g; g=$(verdict "$TMP/c$n.json"); [ "$g" = "$3" ] && pass || fail "expected $3 got $g — $2"; }

# --- DENY: always-executable keys with a command value ---
check "fsmonitor command"        "git config core.fsmonitor '!/tmp/x.sh'"          DENY
check "sshCommand sh -c"         "git config core.sshCommand 'sh -c id'"           DENY

# core.fsmonitor is a boolean or a hook path (git-config(1)). False spellings turn it
# OFF; `true` starts git's own daemon (ASK); any other value is a command (DENY).
check "fsmonitor -c path"        "git -c core.fsmonitor=/tmp/x ls-files"           DENY
check "fsmonitor -c false"       "git -c core.fsmonitor=false ls-files"            ALLOW
check "fsmonitor -c 0"           "git -c core.fsmonitor=0 status"                  ALLOW
check "fsmonitor -c Off quoted"  "git -c 'core.fsmonitor=Off' status"              ALLOW
check "fsmonitor -c path quoted" "git -c 'core.fsmonitor=/tmp/x' status"           DENY
check "fsmonitor -c dq path"     "git -c \"core.fsmonitor=/tmp/x\" status"         DENY
check "fsmonitor config no"      "git config core.fsmonitor no"                    ALLOW
check "fsmonitor env false"      "GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.fsmonitor GIT_CONFIG_VALUE_0=false git status" ALLOW
check "fsmonitor params false"   "GIT_CONFIG_PARAMETERS=\"'core.fsmonitor=false'\" git status" ALLOW
check "fsmonitor -c true"        "git -c core.fsmonitor=true status"               ASK

# --config-env=<key>=<ENVVAR> (git(1)): -c with the value read from an env var. An
# inline assignment is classified; with none the value is invisible: exec key ASKs.
check "config-env sshCommand"    "git --config-env=core.sshCommand=X fetch"        ASK
check "config-env spaced"        "git --config-env core.fsmonitor=X status"        ASK
check "config-env pager"         "git --config-env=core.pager=X log"               ASK
check "config-env inline sh -c"  "X='sh -c id' git --config-env=core.sshCommand=X fetch" DENY
check "config-env inline path"   "X=/tmp/pwn git --config-env=core.fsmonitor=X status"   DENY
check "config-env export path"   "export X=/tmp/pwn; git --config-env core.fsmonitor=X status" DENY
check "config-env inline less"   "X=less git --config-env=core.pager=X log"        ALLOW
check "config-env inline false"  "X=false git --config-env=core.fsmonitor=X status" ALLOW
check "config-env alias quoted"  "alias dg=\"P=delta git --config-env=core.pager=P \"" ALLOW
check "config-env quoted bad"    "alias dg=\"X=/tmp/pwn git --config-env=core.fsmonitor=X status\"" DENY
check "config-env extraheader"   "git --config-env=http.extraheader=GIT_AUTH_HEADER fetch" ALLOW
check "config-env url extraheader" "git -c http.extraHeader= --config-env=http.https://github.com/o/r.git.extraHeader=AUTH clone https://github.com/o/r.git" ALLOW
check "config-env benign key"    "git --config-env=user.email=EMAIL commit -m x"   ALLOW
check "fsmonitor -c falsey path" "git -c core.fsmonitor=false.sh status"           DENY

# --- ASK: exec-capable key with a command-shaped value ---
check "credential.helper bang"   "git config credential.helper '!/tmp/h.sh'"       ASK
check "core.pager script"        "git config core.pager '!/tmp/x.sh'"              ASK
check "alias bang"               "git config alias.st '!/tmp/pwn.sh'"             ASK
check "persistent hooksPath"     "git config core.hooksPath /tmp/hooks"           ASK
check "filter clean cmd"         "git config filter.lfs.clean 'sh -c evil'"       ASK
check "editor node -e"           "git config core.editor 'node -e proc'"          ASK
check "difftool cmd"             "git config difftool.x.cmd 'sh -c d'"            ASK
check "difftool tool path"       "git config difftool.meld.path /tmp/x"           ASK
check "mergetool path via -c"     "git -c mergetool.vim.path=./x mergetool"        ASK
check "browser path config-env"   "git --config-env=browser.ff.path=P help -w log" ASK
check "man path"                  "git config man.foo.path /tmp/x"                 ASK
check "difftool.prompt stays"     "git config difftool.prompt false"              ALLOW
check "sshCommand benign->ASK?"  "git config core.sshCommand 'ssh -i /k'"         ALLOW

# URL/name subsection keys (section.<subsection>.variable): the subsection may hold
# ':' '/' and dots; the variable is the part after the LAST dot. Every form.
U=credential.https://example.com.helper
check "scoped helper config"     "git config $U '!/tmp/h.sh'"                      ASK
check "scoped helper -c"         "git -c '$U=!/tmp/h.sh' fetch"                    ASK
check "scoped helper env pair"   "GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=$U GIT_CONFIG_VALUE_0='!/tmp/h.sh' git fetch" ASK
check "scoped helper params"     "GIT_CONFIG_PARAMETERS=\"'$U=!/tmp/h.sh'\" git fetch" ASK
check "scoped helper config-env" "git --config-env=$U=H fetch"                     ASK
check "scoped fsmonitor -c"      "git -c core.x.y.fsmonitor=/tmp/x status"         DENY
check "remote receivepack"       "git -c remote.my.host.receivepack=/tmp/h.sh push" ASK
check "scoped helper store"      "git config $U store"                             ALLOW
check "scoped extraHeader -c"    "git -c http.https://example.com/.extraHeader=X-Trace:1 fetch" ALLOW
check "scoped extraHeader params" "GIT_CONFIG_PARAMETERS=\"'http.https://example.com/.extraHeader=X-Trace:1'\" git fetch" ALLOW
check "scoped insteadOf"         "git config url.https://github.com/.insteadOf git@github.com:" ALLOW

# Command-valued keys from git-config(1) / gitattributes(5) / git-send-email(1).
check "interactive.diffFilter"   "git -c interactive.diffFilter='/tmp/x.sh' add -p" ASK
check "diffFilter delta"         "git -c interactive.diffFilter='delta --color-only' add -p" ALLOW
check "diff textconv"            "git config diff.pdf.textconv /tmp/x"             ASK
check "merge driver"             "git config merge.ours.driver /tmp/x"             ASK
check "filter process"           "git config filter.lfs.process /tmp/x"            ASK
check "core.gitProxy"            "git config core.gitProxy /tmp/x"                 ASK
check "packObjectsHook"          "git -c uploadpack.packObjectsHook=/tmp/x fetch"  ASK
check "pager.<cmd> bang"         "git config pager.log '!/tmp/x.sh'"               ASK
check "pager.<cmd> false"        "git config pager.log false"                      ALLOW
check "submodule update bang"    "git config submodule.sub.update '!/tmp/x'"       ASK
check "submodule update rebase"  "git config submodule.sub.update rebase"          ALLOW
check "sendemail toCmd"          "git config sendemail.toCmd /tmp/x"               ASK

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

# --- DENY: ext::/fd:: transport helpers + protocol.*.allow=always (RCE) ---
check "clone ext:: transport"    "git clone 'ext::/tmp/x' repo"                   DENY
check "remote add ext::"         "git remote add origin 'ext::helper arg'"        DENY
check "fetch fd:: transport"     "git fetch 'fd::7/data'"                         DENY
check "-c protocol.ext.allow"    "git -c protocol.ext.allow=always clone 'ext::x' r" DENY
check "protocol.file.allow only" "git -c protocol.file.allow=always submodule update --init" DENY

# --- ALLOW: ext:: embedded in a path/URL (not a transport arg) is not a helper ---
check "ext:: inside https url"   "git clone https://ex.com/ext::weird repo"       ALLOW
check "context:: not ext::"      "git log context::main"                          ALLOW

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
