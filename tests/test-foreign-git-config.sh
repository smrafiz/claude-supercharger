#!/usr/bin/env bash
# GitSpawn: a git repo OUTSIDE the project whose .git/config carries an exec-capable
# key (core.fsmonitor, core.hooksPath, core.sshCommand, core.pager/pager.*, a
# non-LFS filter driver) runs that command on an ordinary `git status/diff/log`.
# git-config-exec-guard reads the foreign repo's config (never runs git IN it) and
# ASKs. config-scan gets the same key set for the project's own repo at SessionStart.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

HOOK="$REPO_DIR/hooks/git-config-exec-guard.sh"
SCAN="$REPO_DIR/hooks/config-scan.sh"
echo "=== Foreign Git Config Tests ==="

T=$(mktemp -d); T=$(cd "$T" && pwd -P)
P="$T/proj"; mkdir -p "$P/sub" && git -C "$P" init -q
H="$T/home"; mkdir -p "$H"
CANARY="$T/canary"
# fixture: a foreign repo whose config is written with --file (git never runs in it)
mkrepo() { # dir key value [key value...]
  local d="$1"; shift; mkdir -p "$d"; git init -q "$d" 2>/dev/null
  while [ $# -ge 2 ]; do git config --file "$d/.git/config" "$1" "$2"; shift 2; done
}
PAY="$T/hook"; printf '#!/bin/sh\ntouch %s\n' "$CANARY" > "$PAY"; chmod +x "$PAY"
mkrepo "$T/fsm"    core.fsmonitor "$PAY"
mkrepo "$T/hp"     core.hooksPath "$T/hooks"
mkrepo "$T/ssh"    core.sshCommand "/opt/x/ssh-wrap"
mkrepo "$T/pg"     core.pager "/opt/x/pg"
mkrepo "$T/pgl"    pager.log "/opt/x/pg"
mkrepo "$T/flt"    filter.x.smudge "/opt/x/smudge"
mkrepo "$T/clean"  user.name dev
mkrepo "$T/fsbool" core.fsmonitor true
mkrepo "$T/lfs"    filter.lfs.smudge "git-lfs smudge -- %f" filter.lfs.process "git-lfs filter-process"
mkrepo "$T/pgoff"  pager.branch false
mkrepo "$P/vendor/x" core.fsmonitor "$PAY"
mkrepo "$H/foreign"  core.fsmonitor "$PAY"
# the project's OWN config carries a key too (husky-style): git in the project must not ask
git config --file "$P/.git/config" core.hooksPath .husky
git -C "$P" -c user.name=t -c user.email=t@t.invalid commit -q --allow-empty -m init
git -C "$P" worktree add -q "$P/wt" 2>/dev/null
ln -s "$T/fsm" "$T/link"
ln -s "$T/fsm" "$P/lnk"
ln -s "$P" "$T/plink"

n=0
mkin() { # file cmd cwd
  CMD="$2" CWD="$3" SID="s$n" python3 - "$1" <<'PY'
import json, os, sys
open(sys.argv[1], "w").write(json.dumps({"tool_name": "Bash", "cwd": os.environ["CWD"],
    "tool_input": {"command": os.environ["CMD"]}, "session_id": os.environ["SID"]}))
PY
}
verdict() {
  HOME="$H" CLAUDE_PROJECT_DIR="$P" SUPERCHARGER_STATE="$(mktemp -d)" bash "$HOOK" < "$1" > "$T/o" 2>/dev/null
  python3 -c "import json,sys;s=open(sys.argv[1]).read().strip();print(json.loads(s)['hookSpecificOutput']['permissionDecision'].upper() if s else 'ALLOW')" "$T/o"
}
check() { # name cmd expected [cwd]
  n=$((n+1)); mkin "$T/c$n.json" "$2" "${4:-$P}"; begin_test "$1"; local g; g=$(verdict "$T/c$n.json")
  [ "$g" = "$3" ] && pass || fail "expected $3 got $g — $2"
}

# --- ASK: git aimed at a foreign repo carrying an exec-capable key ---
check "-C foreign status (fsmonitor)"     "git -C $T/fsm status"                        ASK
check "cd foreign && git status"           "cd $T/fsm && git status"                     ASK
check "cd foreign; git status"             "cd $T/fsm; git status"                       ASK
check "--git-dir/--work-tree"              "git --git-dir=$T/fsm/.git --work-tree=$T/fsm status" ASK
check "GIT_DIR= prefix"                    "GIT_DIR=$T/fsm/.git git status"              ASK
check "-C foreign diff (hooksPath)"        "git -C $T/hp diff"                           ASK
check "-C foreign log -p (pager)"          "git -C $T/pg log -p"                         ASK
check "plain-binary sshCommand"            "git -C $T/ssh fetch"                         ASK
check "pager.log plain binary"             "git -C $T/pgl log"                           ASK
check "non-LFS smudge filter"              "git -C $T/flt checkout ."                    ASK
check "trailing slash"                     "git -C $T/fsm/ status"                       ASK
check "symlink to foreign repo"            "git -C $T/link status"                       ASK
check "tilde path"                         "git -C ~/foreign status"                     ASK
check "subdir of foreign repo"             "git -C $T/fsm/.git/.. status"                ASK
check "nested repo inside project"         "cd vendor/x && git status"                   ASK
check "payload cwd is the foreign repo"    "git status"                                  ASK  "$T/fsm"
check "message names the key"              "git -C $T/hp status"                         ASK
grep -q 'core.hookspath' "$T/o" && grep -q "$T/hp" "$T/o" && pass || fail "reason lacks repo/key: $(cat "$T/o")"

# --- ALLOW ---
check "git status in project"              "git status"                                  ALLOW
check "git -C project/sub status"          "git -C $P/sub status"                        ALLOW
check "project via symlink"                "git -C $T/plink status"                      ALLOW
check "foreign repo, clean config"         "git -C $T/clean status"                      ALLOW
check "fsmonitor=true"                     "git -C $T/fsbool status"                     ALLOW
check "git-lfs filters"                    "git -C $T/lfs status"                        ALLOW
check "pager.branch=false"                 "git -C $T/pgoff branch"                      ALLOW
check "non-git command on .git/config"     "cat $T/fsm/.git/config"                      ALLOW
check "cd foreign then non-git"            "cd $T/fsm && ls"                             ALLOW
check "git in project after cd back"       "cd $T/fsm && cd $P && git status"            ALLOW
check "cd /abs/project && git (fork-free)"  "cd $P && git status"                         ALLOW
check "cd /abs/project/sub && git"         "cd $P/sub && git log -p"                     ALLOW
check "cd /abs nested repo && git"         "cd $P/vendor/x && git status"                ASK
check "cd \"/abs nested\" && git (quoted)" "cd \"$P/vendor/x\" && git status"            ASK
check "git, then cd foreign (no git after)" "git status && cd $T/fsm"                    ALLOW
check "cd /abs/project, git -C foreign"    "cd $P && git -C $T/fsm status"               ASK
check "cd sub && git (relative, in project)" "cd sub && git status"                      ALLOW
check "cd symlink-in-project -> foreign"   "cd lnk && git status"                        ASK
check "cd /abs/symlink-in-project"         "cd $P/lnk && git status"                     ASK
check "linked worktree of the project"     "cd wt && git status"                         ALLOW
check "payload cwd is project worktree"    "git status"                                  ALLOW "$P/wt"

begin_test "missing lib asks instead of passing silently"
HC=$(mktemp -d); cp "$REPO_DIR"/hooks/git-config-exec-guard.sh "$REPO_DIR"/hooks/lib-*.sh "$HC/"
mkin "$T/nl.json" "git -C $T/fsm status" "$P"
HOME="$H" CLAUDE_PROJECT_DIR="$P" SUPERCHARGER_STATE="$(mktemp -d)" bash "$HC/git-config-exec-guard.sh" < "$T/nl.json" > "$T/o" 2>/dev/null
grep -q '"ask"' "$T/o" && grep -q 'lib_config_checks' "$T/o" && pass || fail "no ask without lib: $(cat "$T/o")"
rm -rf "$HC"

begin_test "hook never runs git inside the foreign repo (fsmonitor canary)"
[ -e "$CANARY" ] && fail "fsmonitor payload fired" || pass

# --- config-scan: same key set for the project's own repo at SessionStart ---
scan() { printf '{"cwd":"%s","session_id":"s","hook_event_name":"SessionStart","source":"startup"}' "$(native_path "$1")" \
  | HOME="$H" SUPERCHARGER_STATE="$2" bash "$SCAN" 2>/dev/null; }
ST=$(mktemp -d); i=0
# repo dirs are numbered: watchPaths echo the dir, so a key-named dir would match the grep
for spec in "core.hooksPath|$T/hooks" "core.sshCommand|/opt/x/ssh-wrap" "core.pager|/opt/x/pg"; do
  i=$((i+1)); R="$T/own$i"; mkrepo "$R" "${spec%%|*}" "${spec#*|}"
  begin_test "config-scan: own repo ${spec%%|*} warns"
  OUT=$(scan "$R" "$ST"); echo "$OUT" | grep -qi "${spec%%|*}" && pass || fail "no warning: $OUT"
  begin_test "config-scan: own repo ${spec%%|*} warns once, not every session"
  OUT=$(scan "$R" "$ST"); echo "$OUT" | grep -qi "${spec%%|*}" && fail "re-warned: $OUT" || pass
done
for spec in "core.fsmonitor|true" "pager.branch|false" "core.pager|less"; do
  i=$((i+1)); R="$T/ok$i"; mkrepo "$R" "${spec%%|*}" "${spec#*|}"
  begin_test "config-scan: own repo ${spec%%|*}=${spec#*|} is quiet"
  OUT=$(scan "$R" "$(mktemp -d)"); echo "$OUT" | grep -qi "${spec%%|*}" && fail "warned: $OUT" || pass
done
begin_test "config-scan: fsmonitor script still warns every session"
OUT=$(scan "$T/fsm" "$ST"); OUT2=$(scan "$T/fsm" "$ST")
echo "$OUT2" | grep -qi "core.fsmonitor" && pass || fail "fsmonitor not re-warned: $OUT2"

rm -rf "$T" "$ST"
report
