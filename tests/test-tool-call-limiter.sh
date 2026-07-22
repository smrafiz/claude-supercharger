#!/usr/bin/env bash
# Suite for tool-call-limiter.sh (v2.21.13).
# The maxToolCalls config path was string-interpolated into a python literal, so
# a project dir containing a single quote (o'malley) broke the string →
# SyntaxError → CAP empty → the limiter silently disabled itself. The path is
# now passed via env, so an apostrophe in the path still enforces the cap.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
H="$REPO_DIR/hooks/tool-call-limiter.sh"

# rc: run the limiter once for a project already at its cap → 2 means it blocked
at_cap_rc() { # <project_dir>
  local state proj="$1"
  state=$(mktemp -d); mkdir -p "$state/scope"
  printf '1\n' > "$state/scope/.tool-calls-tclsess"   # already 1 call; cap is 1
  local j; j=$(printf '{"tool_name":"Bash","cwd":"%s","tool_input":{"command":"ls"}}' "$proj")
  CLAUDE_SESSION_ID=tclsess SUPERCHARGER_STATE="$state" bash "$H" >/dev/null 2>&1 <<<"$j"
  local rc=$?
  rm -rf "$state"
  echo "$rc"
}

# control: a normal path enforces the cap
begin_test "tool-call-limiter: blocks past cap for a normal path"
BASE=$(mktemp -d); P="$BASE/normal-proj"; mkdir -p "$P"; printf '{"maxToolCalls":1}' > "$P/.supercharger.json"
[ "$(at_cap_rc "$P")" = 2 ] && pass || fail "limiter did not block past cap for a normal path"
rm -rf "$BASE"

# the fix: a path with a single quote must still enforce the cap
begin_test "tool-call-limiter: apostrophe in path still enforces the cap (no SyntaxError disable)"
BASE=$(mktemp -d); P="$BASE/o'malley-proj"; mkdir -p "$P"; printf '{"maxToolCalls":1}' > "$P/.supercharger.json"
[ "$(at_cap_rc "$P")" = 2 ] && pass || fail "apostrophe path disabled the limiter (config parse broke)"
rm -rf "$BASE"

# ---- 2.22.7: per-session counter keyed on the PAYLOAD session_id ----
# rc for a project at cap under a given payload session id
sid_rc() { # <project_dir> <state_dir> <session_id>
  printf '1\n' > "$2/scope/.tool-calls-$3"   # seed session $3 at the cap (1)
  local j; j=$(printf '{"tool_name":"Bash","cwd":"%s","session_id":"%s","tool_input":{"command":"ls"}}' "$1" "$3")
  env -u CLAUDE_SESSION_ID SUPERCHARGER_STATE="$2" bash "$H" >/dev/null 2>&1 <<<"$j"; echo $?
}
begin_test "tool-call-limiter: uses payload session_id — session B not blocked by session A"
BASE=$(mktemp -d); P="$BASE/proj"; mkdir -p "$P"; printf '{"maxToolCalls":1}' > "$P/.supercharger.json"
ST=$(mktemp -d); mkdir -p "$ST/scope"
A=$(sid_rc "$P" "$ST" "sessA")   # sessA already at cap -> this call is over -> block (2)
B=$(sid_rc "$P" "$ST" "sessB")   # sessB independent counter -> seeded 1, this is 2nd -> also block? seed=1 -> block
# sessA blocked, and sessA's file must be distinct from sessB's (no shared daily counter)
if [ "$A" = 2 ] && [ -f "$ST/scope/.tool-calls-sessA" ] && [ -f "$ST/scope/.tool-calls-sessB" ] && [ ! -f "$ST/scope/.tool-calls-$(date +%Y%m%d)" ]; then pass
else fail "counter not keyed on payload session_id (A=$A; daily=$([ -f "$ST/scope/.tool-calls-$(date +%Y%m%d)" ] && echo yes || echo no))"; fi
rm -rf "$BASE" "$ST"

report
