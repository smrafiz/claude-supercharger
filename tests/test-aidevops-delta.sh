#!/usr/bin/env bash
# 2026-11-11: env vars that make git or zsh run a program, found by diffing
# marcusquinn/aidevops's command policy against our Bash guards. Every attack row
# here was ALLOWED by the previous hooks; the allow rows pin the false-positive side.
# The credential-directory half of the same delta lives in test-env-file-guard.sh
# and test-secret-directory.sh.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
export SUPERCHARGER_HOME="$REPO_DIR"

echo "=== aidevops delta (exec env vars) ==="

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/home"
n=0
# check <hook> <expected deny|ask|allow> <name> <command>
check() {
  n=$((n+1))
  CMD="$4" python3 -c "import json,os;print(json.dumps({'tool_name':'Bash','tool_input':{'command':os.environ['CMD']},'cwd':'/tmp','session_id':'aidv$n'}))" > "$TMP/in$n"
  begin_test "$3"
  local out rc got=allow
  out=$(HOME="$TMP/home" SUPERCHARGER_STATE="$TMP/state$n" bash "$REPO_DIR/hooks/$1" < "$TMP/in$n" 2>/dev/null); rc=$?
  [ "$rc" -eq 2 ] && got=deny
  case "$out" in *'"deny"'*) got=deny ;; *'"ask"'*) got=ask ;; esac
  [ "$got" = "$2" ] && pass || fail "expected $2, got $got — $4"
}

# 1. GIT_CONFIG_PARAMETERS: the third spelling of `git -c` (git-config-exec-guard.sh)
check git-config-exec-guard.sh deny  "PARAMETERS sshCommand shell"    "GIT_CONFIG_PARAMETERS=\"'core.sshcommand=sh -c id'\" git fetch"
check git-config-exec-guard.sh deny  "PARAMETERS fsmonitor, k'='v"   "GIT_CONFIG_PARAMETERS=\"'core.fsmonitor'='./x'\" git status"
check git-config-exec-guard.sh ask   "PARAMETERS hooksPath unquoted" "GIT_CONFIG_PARAMETERS=core.hooksPath=/tmp/h git commit -m x"
check git-config-exec-guard.sh deny  "PARAMETERS second pair"        "GIT_CONFIG_PARAMETERS=\"'user.name=x' 'core.fsmonitor=./x'\" git status"
check git-config-exec-guard.sh allow "PARAMETERS benign key"         "GIT_CONFIG_PARAMETERS=\"'core.pager=less'\" git log"

# 2. git runs a program named by the environment (env-exec-guard.sh)
check env-exec-guard.sh ask   "GIT_PROXY_COMMAND"                 "GIT_PROXY_COMMAND=/tmp/p.sh git fetch git://h/r"
check env-exec-guard.sh ask   "GIT_EXEC_PATH"                     "GIT_EXEC_PATH=/tmp/evil git status"
check env-exec-guard.sh ask   "export GIT_PROXY_COMMAND"          "export GIT_PROXY_COMMAND=./proxy"

# 3. zsh startup dir (env-exec-guard.sh)
check env-exec-guard.sh ask   "ZDOTDIR"                           "ZDOTDIR=/tmp/evil zsh -i -c true"
check env-exec-guard.sh allow "reading ZDOTDIR"                   "echo \$ZDOTDIR"
check env-exec-guard.sh allow "git --exec-path query"             "git --exec-path"

report
