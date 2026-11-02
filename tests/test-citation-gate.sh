#!/usr/bin/env bash
# citation-gate (4.4.3): a URL in the reply that appeared nowhere else in the
# session (prompt, tool call, tool result) is named as possibly invented.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

HOOK="$REPO_DIR/hooks/citation-gate.sh"
echo "=== Citation gate ==="
T=$(mktemp -d)

# Transcript lines, Claude Code's shapes.
prompt()  { jq -nc --arg t "$1" '{type:"user",message:{role:"user",content:$t}}'; }
said()    { jq -nc --arg t "$1" '{type:"assistant",message:{role:"assistant",content:[{type:"text",text:$t}]}}'; }
fetched() { jq -nc --arg u "$1" '{type:"assistant",message:{role:"assistant",content:[{type:"tool_use",name:"WebFetch",input:{url:$u,prompt:"x"}}]}}'; }
result()  { jq -nc --arg t "$1" '{type:"user",message:{role:"user",content:[{type:"tool_result",tool_use_id:"t1",content:$t}]}}'; }

run() { # transcript-file [extra-env] -> the hook's stdout
  jq -nc --arg p "$1" '{session_id:"cg",transcript_path:$p,stop_hook_active:false}' \
    | env ${2:-} bash "$HOOK" 2>/dev/null
}
check() { # name file expect(warn:<url>|quiet) [env]
  begin_test "$1"
  local out; out=$(run "$2" "${4:-}")
  case "$3" in
    quiet) [ -z "$out" ] && pass || fail "expected silence, got: $out" ;;
    warn:*) case "$out" in *systemMessage*"${3#warn:}"*) pass ;; *) fail "expected a warning naming ${3#warn:}, got: ${out:-<nothing>}" ;; esac ;;
  esac
}

F=$T/invented.jsonl
{ prompt "what does the spec say"; said "See https://docs.madeup-site.io/spec/v3 for details."; } > "$F"
check "an invented URL is named" "$F" "warn:https://docs.madeup-site.io/spec/v3"

F=$T/fetched.jsonl
{ prompt "check the spec"; fetched "https://www.rfc-editor.org/rfc/rfc9110"; result "HTTP Semantics ..."; said "Per https://www.rfc-editor.org/rfc/rfc9110#section-15, 402 is reserved."; } > "$F"
check "a URL Claude fetched (anchor ignored) is quiet" "$F" quiet

F=$T/result.jsonl
{ prompt "open a PR"; result "https://github.com/acme/app/pull/12"; said "Opened https://github.com/acme/app/pull/12."; } > "$F"
check "a URL a tool printed is quiet" "$F" quiet

F=$T/pasted.jsonl
{ prompt "review https://github.com/acme/lib please"; said "https://github.com/acme/lib is a small library."; } > "$F"
check "a URL the user pasted is quiet" "$F" quiet

F=$T/selfcite.jsonl
{ prompt "q1"; said "Try https://tools.madeup-site.io/x"; prompt "and again?"; said "As before: https://tools.madeup-site.io/x"; } > "$F"
check "a URL only Claude itself said earlier is still named" "$F" "warn:https://tools.madeup-site.io/x"

F=$T/placeholder.jsonl
{ prompt "q"; said "Point it at http://localhost:3000/api or https://example.com/hook."; } > "$F"
check "placeholder hosts are quiet" "$F" quiet

F=$T/oldturn.jsonl
{ prompt "q1"; said "https://old.madeup-site.io/a"; prompt "q2"; said "No links here."; } > "$F"
check "only the latest reply is checked" "$F" quiet

check "SUPERCHARGER_CITATION_GATE=0 turns it off" "$T/invented.jsonl" quiet "SUPERCHARGER_CITATION_GATE=0"

begin_test "stop_hook_active: never re-enters"
out=$(jq -nc --arg p "$T/invented.jsonl" '{session_id:"cg",transcript_path:$p,stop_hook_active:true}' | bash "$HOOK" 2>/dev/null)
[ -z "$out" ] && pass || fail "got: $out"

begin_test "registration: citation-gate on Stop (lib + plugin)"
grep -q 'Stop|\*|${hooks_dir}/citation-gate.sh' "$REPO_DIR/lib/hooks.sh" && grep -q 'citation-gate.sh' "$REPO_DIR/hooks/hooks.json" && pass || fail "not registered"

rm -rf "$T"
report
