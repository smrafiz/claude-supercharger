#!/usr/bin/env bash
# trust-receipts: a local record of each outward action that ran (push, publish,
# send, upload), counted once at the next session start, listed by /sc-receipts.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

HOOK="$REPO_DIR/hooks/trust-receipts.sh"
TD=$(mktemp -d); trap 'rm -rf "$TD"' EXIT
ST="$TD/state"; R="$ST/receipts"; mkdir -p "$ST"
A=aaaaaaaa-1111-2222-3333-444444444444
B=bbbbbbbb-1111-2222-3333-444444444444
P=/work/proj
fire() { SUPERCHARGER_STATE="$ST" bash "$HOOK" 2>/dev/null; }
# MSYS_NO_PATHCONV: Git Bash would rewrite the /work/proj argv to C:/Program Files/Git/work/proj.
post() { # tool tool_input-json [response] -- compact, as Claude Code sends it
  MSYS_NO_PATHCONV=1 python3 -c 'import json,sys; print(json.dumps({"hook_event_name":"PostToolUse","session_id":sys.argv[1],"cwd":sys.argv[2],
"tool_name":sys.argv[3],"tool_input":json.loads(sys.argv[4]),"tool_response":sys.argv[5]},separators=(",",":")))' \
    "$A" "$P" "$1" "$2" "${3:-ok}" | fire; }
bash_call() { post Bash "$(python3 -c 'import json,sys; print(json.dumps({"command":sys.argv[1]}))' "$1")"; }
start() { printf '{"hook_event_name":"SessionStart","session_id":"%s","cwd":"%s","source":"startup"}' "$1" "${2:-$P}" | fire; }
count() { cat "$R"/*.jsonl 2>/dev/null | grep -c . ; }
last() { tail -n 1 "$R"/*.jsonl 2>/dev/null | tr -d '\r'; }
reset() { rm -rf "$R"; }

echo "=== Trust Receipts Tests ==="

begin_test "receipts: git push is recorded with its destination"
bash_call "git push origin master"
last | grep -q '"kind": "push"' && last | grep -q '"dest": "origin master"' && pass || fail "got: $(last)"

begin_test "receipts: git push from the PowerShell tool is recorded too"
reset; post PowerShell '{"command":"git push origin master"}'
last | grep -q '"kind": "push"' && pass || fail "got: $(last)"

begin_test "receipts: a push inside a commit message is not a push"
reset; bash_call 'git commit -m "fix; git push later"'
[ "$(count)" = 0 ] && pass || fail "false receipt: $(last)"

begin_test "receipts: reads and dry runs leave nothing"
reset
for c in "git log | grep push" "gh pr view 166" "curl -fsSL https://example.com/x" "scp me@host:/tmp/a ." \
         "npm publish --dry-run" "git push --dry-run origin main" "echo git push"; do bash_call "$c"; done
[ "$(count)" = 0 ] && pass || fail "recorded: $(cat "$R"/*.jsonl)"

begin_test "receipts: gh writes, uploads and publishes are recorded"
reset
for c in "gh pr merge 166 --squash" "curl -X POST -d @f https://api.example.com/v1" \
         "rsync -av dist/ srv:/var/www" "npm publish" "FOO=1 docker push img:1"; do bash_call "$c"; done
K=$(tr -d '\r' < "$R"/*.jsonl | python3 -c 'import json,sys; print(" ".join(json.loads(l)["kind"] for l in sys.stdin))')
[ "$K" = "repo upload upload publish push" ] && pass || fail "kinds: $K"

begin_test "receipts: spaced JSON is read too"
reset
printf '{"hook_event_name": "PostToolUse", "session_id": "%s", "cwd": "%s", "tool_name": "Bash", "tool_input": {"command": "git push"}}' "$A" "$P" | fire
[ "$(count)" = 1 ] && pass || fail "spaced payload dropped"

begin_test "receipts: an MCP send keeps the recipient's domain, not the address"
reset; post mcp__claude_ai_Gmail__send_email '{"to":["pat@corp.example","x@other.example"],"body":"private text"}'
last | grep -q '@corp.example' && ! last | grep -q 'pat@' && ! last | grep -q 'private text' && pass || fail "got: $(last)"

begin_test "receipts: MCP reads are skipped; a plugin-namespaced send is not"
reset
post mcp__claude_ai_Google_Drive__get_file_permissions '{"fileId":"1"}'
post mcp__context7__supercharger__resolve-library-id '{"libraryName":"x"}'
post mcp__claude-in-chrome__tabs_create_mcp '{}'
post mcp__plugin_team_slack__postMessage '{"channel":"C1"}'
[ "$(count)" = 1 ] && last | grep -q 'postMessage C1' && pass || fail "got: $(cat "$R"/*.jsonl 2>/dev/null)"

begin_test "receipts: Artifact publish is recorded, read is not"
reset
post Artifact '{"action":"read","url":"https://claude.ai/artifact/x"}'
post Artifact '{"file_path":"/s/page.html"}' "Published https://claude.ai/code/artifact/abc-123"
[ "$(count)" = 1 ] && last | grep -q 'artifact/abc-123' && last | grep -q 'publish page.html' && pass || fail "got: $(last)"

begin_test "receipts: secrets in a destination are masked"
reset; KEY="AKIA""ABCDEFGHIJKLMNOP"
bash_call "git push https://user:hunter2pass@github.com/a/b.git main"
bash_call "docker push reg.example/$KEY:1"
! grep -q 'hunter2pass' "$R"/*.jsonl && ! grep -q "$KEY" "$R"/*.jsonl && [ "$(count)" = 2 ] && pass || fail "leaked: $(cat "$R"/*.jsonl)"

begin_test "receipts: a large tool output after the input still records"
reset
# Built inside python: one 400KB argv string is past Linux's 128KB per-argument limit.
MSYS_NO_PATHCONV=1 python3 -c 'import json,sys; print(json.dumps({"hook_event_name":"PostToolUse","session_id":sys.argv[1],"cwd":sys.argv[2],
"tool_name":"Bash","tool_input":{"command":"git push origin main"},"tool_response":"x"*400000},separators=(",",":")))' "$A" "$P" | fire
[ "$(count)" = 1 ] && pass || fail "big payload dropped"

begin_test "receipts: the next session here gets one count line"
reset; bash_call "git push origin main"; post mcp__claude_ai_Gmail__send_email '{"to":"a@b.example"}'
OUT=$(start "$B")
printf '%s' "$OUT" | grep -q '2 outward action(s): 1 push, 1 send' && pass || fail "got: $OUT"

begin_test "receipts: said once, and silent for another project or the same session"
[ -z "$(start "$B")" ] && [ -z "$(start "$B" /work/other)" ] && pass || fail "repeated"
reset; bash_call "git push"
[ -z "$(start "$A")" ] && pass || fail "own session counted"

begin_test "receipts: output is valid SessionStart JSON"
reset; bash_call "git push"
start "$B" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["hookSpecificOutput"]["hookEventName"]=="SessionStart"' \
  && pass || fail "bad JSON"

begin_test "receipts: SUPERCHARGER_RECEIPTS=0 records nothing"
reset
printf '{"hook_event_name":"PostToolUse","session_id":"%s","cwd":"%s","tool_name":"Bash","tool_input":{"command":"git push"}}' "$A" "$P" \
  | SUPERCHARGER_RECEIPTS=0 SUPERCHARGER_STATE="$ST" bash "$HOOK" 2>/dev/null
[ "$(count)" = 0 ] && pass || fail "recorded while off"

begin_test "receipts: /sc-receipts lists them, and filters by session"
reset; bash_call "git push origin main"
OUT=$(SUPERCHARGER_STATE="$(native_path "$ST")" python3 "$(native_path "$REPO_DIR/tools/receipts.py")" today | tr -d '\r')
OTHER=$(SUPERCHARGER_STATE="$(native_path "$ST")" CLAUDE_CODE_SESSION_ID="$B" python3 "$(native_path "$REPO_DIR/tools/receipts.py")" session | tr -d '\r')
printf '%s' "$OUT" | grep -q '| push | proj | origin main |' && printf '%s' "$OTHER" | grep -q 'No outward actions' \
  && pass || fail "today: $OUT / session: $OTHER"

begin_test "receipts: registered async on PostToolUse and on SessionStart"
jq -e '([.hooks.PostToolUse[]|select(.hooks[].command|test("trust-receipts"))|.hooks[].async]==[true])
  and ([.hooks.PostToolUse[]|select(.hooks[].command|test("trust-receipts"))|.matcher|test("mcp__\\.\\*")]==[true])
  and ([.hooks.SessionStart[].hooks[]|select(.command|test("trust-receipts"))]|length==1)' "$REPO_DIR/hooks/hooks.json" >/dev/null \
  && pass || fail "registration"

report
