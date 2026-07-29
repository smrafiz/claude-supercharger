#!/usr/bin/env bash
# v2.23.45 statusline render cache: a repeat render within the same wall-clock
# second is served from cache (skips the python fork) and must be byte-identical.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

SL="$REPO_DIR/hooks/statusline.sh"
export SUPERCHARGER_HOME="$REPO_DIR"

echo "=== Statusline Render Cache Tests ==="

ST=$(mktemp -d); mkdir -p "$ST/scope"
SID="slcache-test"; CACHE="$ST/scope/.statusline-cache-$SID"
# json.dumps shape (space after the colon) — the parser must tolerate it
PAY=$(python3 -c 'import json,sys;print(json.dumps({"model":{"display_name":"Opus 5"},"cwd":sys.argv[1],"session_id":"slcache-test","transcript_path":"/dev/null","workspace":{"current_dir":sys.argv[1]}}))' "$REPO_DIR")
_render() { printf '%s' "${1:-$PAY}" | SUPERCHARGER_STATE="$ST" bash "$SL" 2>/dev/null; }

begin_test "cold render produces output and writes the cache"
rm -f "$CACHE"
COLD=$(_render)
{ [ -n "$COLD" ] && [ -f "$CACHE" ]; } && pass || fail "no output or no cache file"

begin_test "cached render is byte-identical to the cold one"
WARM=$(_render)
[ "$WARM" = "$COLD" ] && pass || fail "cached output differs from cold"

begin_test "cache key includes cwd — a different cwd is not served the stale line"
PAY2=$(python3 -c 'import json;print(json.dumps({"model":{"display_name":"Opus 5"},"cwd":"/tmp","session_id":"slcache-test","transcript_path":"/dev/null","workspace":{"current_dir":"/tmp"}}))')
OTHER=$(_render "$PAY2")
[ "$OTHER" != "$COLD" ] && pass || fail "served another cwd's cached line"

begin_test "entry expires — a later second re-renders"
_render >/dev/null; S1=$(head -1 "$CACHE" 2>/dev/null)
sleep 1.2
_render >/dev/null; S2=$(head -1 "$CACHE" 2>/dev/null)
{ [ -n "$S1" ] && [ "$S1" != "$S2" ]; } && pass || fail "stamp did not advance ($S1 -> $S2)"

begin_test "session id with unsafe characters disables the cache (no path escape)"
BADPAY=$(python3 -c 'import json;print(json.dumps({"model":{"display_name":"x"},"cwd":"/tmp","session_id":"../../evil","transcript_path":"/dev/null"}))')
_render "$BADPAY" >/dev/null 2>&1
ls "$ST/scope/".statusline-cache-*evil* >/dev/null 2>&1 && fail "wrote a cache file for an unsafe session id" || pass

begin_test "still renders nothing when /sc off"
DIS=".supercharger-""disabled"; printf 'x\n' > "$ST/scope/$DIS"
OFF=$(_render)
rm -f "$ST/scope/$DIS"
[ -z "$OFF" ] && pass || fail "rendered output while disabled"

rm -rf "$ST"
report
