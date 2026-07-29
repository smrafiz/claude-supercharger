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

report
