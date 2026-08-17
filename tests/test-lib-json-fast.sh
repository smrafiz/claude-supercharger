#!/usr/bin/env bash
# The fork-free JSON reader must agree with jq on every value it CLAIMS, and must
# refuse (non-zero) anything it can't be certain about. A wrong claim silently
# corrupts 4 hot-path hooks, so the bar is: correct, or explicitly fall back.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
# shellcheck source=hooks/lib-json-fast.sh
. "$REPO_DIR/hooks/lib-json-fast.sh"

echo "=== lib-json-fast Tests ==="

# claims $2 for key $1 in body $3
ok() { begin_test "$1"; if _json_fast_str "$2" "$4" && [ "$_JSON_FAST_VAL" = "$3" ]; then pass; else fail "got rc=$? val='$_JSON_FAST_VAL' want '$3'"; fi; }
# must REFUSE (rc != 0)
no() { begin_test "$1"; if _json_fast_str "$2" "$3"; then fail "claimed '$_JSON_FAST_VAL' but should have fallen back"; else pass; fi; }

ok "compact form"            cwd "/a/b" '{"cwd":"/a/b","x":1}'
ok "pretty form (space)"     cwd "/a/b" '{"cwd": "/a/b", "x": 1}'
ok "value with spaces"       command "npm install lodash" '{"command": "npm install lodash"}'
ok "last key in object"      tool_name "Bash" '{"cwd":"/x","tool_name":"Bash"}'
ok "empty string value"      cwd "" '{"cwd":"","a":"b"}'
ok "value with / and ."      file_path "/p/a.b.ts" '{"file_path":"/p/a.b.ts"}'

# --- must fall back, never guess ---
no "key absent"              cwd '{"tool_name":"Bash"}'
no "duplicate key"           cwd '{"cwd":"/a","z":{"cwd":"/b"}}'
no "escaped quote in value"  command '{"command":"echo \"hi\""}'
no "backslash in value"      command '{"command":"C:\\Temp"}'
no "unicode escape"          cwd '{"cwd":"/a\u0062"}'
no "non-string (number)"     timeout '{"timeout":30}'
no "non-string (object)"     tool_input '{"tool_input":{"command":"ls"}}'
no "empty body"              cwd ''

# --- key-prefix confusion must NOT produce a wrong claim ---
begin_test "a longer key ending in the name is not matched"
if _json_fast_str cwd '{"old_cwd":"/wrong"}'; then fail "matched old_cwd -> '$_JSON_FAST_VAL'"; else pass; fi

begin_test "an escaped key-lookalike inside another value does not match"
# the inner \"cwd\":\" has backslashes, so the literal `"cwd":` never appears there
B='{"note":"see \"cwd\" docs","cwd":"/real"}'
if _json_fast_str cwd "$B"; then
  [ "$_JSON_FAST_VAL" = "/real" ] && pass || fail "claimed wrong value '$_JSON_FAST_VAL'"
else
  pass   # falling back is also acceptable
fi

# --- differential vs jq on realistic payloads: never disagree when it claims ---
begin_test "agrees with jq on every claim across realistic payloads (any-depth lookup)"
BAD=""
for B in \
  '{"session_id":"s1","tool_name":"Bash","tool_input":{"command":"git status"},"cwd":"/Users/x/p"}' \
  '{"cwd": "/Users/x/my proj", "tool_name": "Read"}' \
  '{"tool_name":"Write","tool_input":{"file_path":"/p/a.ts"},"cwd":"/p"}' \
  '{"tool_input":{"command":"npm install lodash"},"cwd":"/tmp/t"}' ; do
  for K in cwd tool_name command file_path session_id; do
    if _json_fast_str "$K" "$B"; then
      # the contract is an ANY-DEPTH unique lookup, so compare against a recursive jq
      JQV=$(printf '%s' "$B" | jq -r --arg k "$K" \
        '[..|objects|select(has($k))|.[$k]|select(type=="string")]|first // empty' 2>/dev/null)
      [ "$_JSON_FAST_VAL" = "$JQV" ] || BAD="$BAD [$K: fast='$_JSON_FAST_VAL' jq='$JQV']"
    fi
  done
done
[ -z "$BAD" ] && pass || fail "disagreements:$BAD"

begin_test "refuses when the same name exists at two depths (the real ambiguity risk)"
if _json_fast_str command '{"command":"outer","tool_input":{"command":"inner"}}'; then
  fail "claimed '$_JSON_FAST_VAL' from an ambiguous payload"
else pass; fi

# --- v2.27.28 prefix retry ----------------------------------------------------
# _json_fast_str's size gate sent every large payload to jq, but these callers
# want TOP-LEVEL fields and Claude Code puts those at the FRONT — so a hook that
# needed only the session id forked jq on every call with tool output attached.
# _json_get now retries on a bounded prefix. jq stays the oracle in all three.
begin_test "a top-level field in a LARGE payload is read without forking jq"
BIG=$(python3 -c "import json,sys;print(json.dumps({'session_id':'sess-abc','cwd':'/repo/proj','tool_response':{'stdout':'z'*20000}}))")
SHIM=$(mktemp -d); JQLOG="$SHIM/jq.log"
printf '#!/bin/bash\necho jq >> "%s"\nexec %s "$@"\n' "$JQLOG" "$(command -v jq)" > "$SHIM/jq"
chmod +x "$SHIM/jq"; : > "$JQLOG"
GOT=$(PATH="$SHIM:$PATH" bash -c '. "$1"; _json_get V session_id "$2" ".session_id // empty"; printf "%s" "$V"' \
  _ "$REPO_DIR/hooks/lib-json-fast.sh" "$BIG")
NF=$(grep -c jq "$JQLOG" 2>/dev/null | tr -d ' '); NF=${NF:-0}
[ "$GOT" = "sess-abc" ] && [ "$NF" -eq 0 ] && pass || fail "value='$GOT' jq_forks=$NF (expected sess-abc / 0)"

# The guard that makes truncation safe: cutting mid-string can leave a value with
# no closing quote, and the slicer would hand back the fragment AS IF whole — a
# silently wrong session id, i.e. the per-session-file scoping bug class again.
begin_test "a value straddling the prefix boundary is NOT truncated — it defers to jq"
BAD=""
for PADLEN in 1900 1980 2000 2040 2047 2048 2049 2100; do
  P=$(python3 -c "
import json,sys
pad='p'*int(sys.argv[1])
print(json.dumps({'pad':pad,'cwd':'v'*300,'session_id':'straddle','tool_response':{'stdout':'q'*9000}}))" "$PADLEN")
  TRUTH=$(printf '%s' "$P" | jq -r '.cwd // empty')
  GOT=$(bash -c '. "$1"; _json_get V cwd "$2" ".cwd // empty"; printf "%s" "$V"' _ "$REPO_DIR/hooks/lib-json-fast.sh" "$P")
  [ "$GOT" = "$TRUTH" ] || BAD="$BAD [pad=$PADLEN got ${#GOT} chars, want ${#TRUTH}]"
done
[ -z "$BAD" ] && pass || fail "truncated value accepted:$BAD"

begin_test "the depth check still holds on the prefix path (nested key not mistaken for top level)"
NEST=$(python3 -c "import json;print(json.dumps({'other':{'cwd':'/nested'},'workspace':{'current_dir':'/correct'},'blob':'b'*9000}))")
GOT=$(bash -c '. "$1"; _json_get V cwd "$2" ".cwd // .workspace.current_dir // empty"; printf "%s" "$V"' \
  _ "$REPO_DIR/hooks/lib-json-fast.sh" "$NEST")
[ "$GOT" = "/correct" ] && pass || fail "took '$GOT', expected /correct (the nested cwd must not win)"
rm -rf "$SHIM"

report
