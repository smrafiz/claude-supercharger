#!/usr/bin/env bash
# 2026-11-23: models on the user's ask list (default Fable) must be approved by the user.
#  - model-ask-guard.sh PreToolUse Agent: the call's model, or the agent file's model:
#  - model-ask-guard.sh Stop: the session answering on a listed model is reported once
#  - safety.sh: a shell command selecting a listed model
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

echo "=== Model ask guard ==="
setup_test_home
ST="$TEST_HOME/state"; mkdir -p "$ST/scope" "$TEST_HOME/.claude/agents"

decision() { # hook input [env...] -> ASK / DENY / ok
  local h="$1" in="$2" out; shift 2
  out=$(printf '%s' "$in" | env HOME="$TEST_HOME" SUPERCHARGER_STATE="$ST" "$@" bash "$REPO_DIR/hooks/$h" 2>/dev/null)
  case "$out" in *'"deny"'*) echo DENY ;; *'"ask"'*) echo ASK ;; *) echo ok ;; esac
}
bash_in() { jq -nc --arg c "$1" '{session_id:"ma",tool_name:"Bash",tool_input:{command:$c},cwd:"/tmp"}'; }
agent_in() { jq -nc --arg m "$1" --arg t "$2" '{session_id:"ma",tool_name:"Agent",cwd:"/tmp",tool_input:({description:"d",prompt:"p"} + (if $m=="" then {} else {model:$m} end) + (if $t=="" then {} else {subagent_type:$t} end))}'; }

while IFS='|' read -r want cmd; do
  [ -n "$cmd" ] || continue
  begin_test "safety: $want for: $cmd"
  got=$(decision safety.sh "$(bash_in "$cmd")")
  [ "$got" = "$want" ] && pass || fail "got $got"
done <<'EOF'
ASK|claude --model fable -p "hi"
ASK|claude --model=claude-fable-5-2 -p hi
ASK|ANTHROPIC_MODEL=claude-fable-5-2 claude -p hi
ASK|curl https://api.anthropic.com/v1/messages -d '{"model":"claude-fable-5-2","max_tokens":5}'
ASK|claude -p hi --model FABLE
ok|claude --model opus -p hi
ok|cat docs/fable-notes.md
ok|git commit -m "docs: never use the fable model"
ok|grep -rn fable src/
EOF

begin_test "SUPERCHARGER_MODEL_ASK='' turns the Bash check off"
[ "$(decision safety.sh "$(bash_in 'claude --model fable -p hi')" SUPERCHARGER_MODEL_ASK=)" = ok ] && pass || fail "still asked"
begin_test "SUPERCHARGER_MODEL_ASK=haiku asks for haiku, not fable"
a=$(decision safety.sh "$(bash_in 'claude --model haiku -p hi')" SUPERCHARGER_MODEL_ASK=haiku)
b=$(decision safety.sh "$(bash_in 'claude --model fable -p hi')" SUPERCHARGER_MODEL_ASK=haiku)
[ "$a$b" = ASKok ] && pass || fail "haiku=$a fable=$b"

begin_test "Agent with model fable asks; opus and no model do not"
a=$(decision model-ask-guard.sh "$(agent_in fable '')")
b=$(decision model-ask-guard.sh "$(agent_in opus '')")
c=$(decision model-ask-guard.sh "$(agent_in '' general-purpose)")
[ "$a$b$c" = ASKokok ] && pass || fail "fable=$a opus=$b none=$c"

printf -- '---\nname: Storyteller (Writer)\ndescription: x\nmodel: fable\n---\nbody\n' > "$TEST_HOME/.claude/agents/storyteller.md"
printf -- '---\nname: plain\nmodel: sonnet\n---\nfable mentioned in the body only\n' > "$TEST_HOME/.claude/agents/plain.md"
begin_test "an agent whose definition file says model: fable asks (by frontmatter name and by file name)"
a=$(decision model-ask-guard.sh "$(agent_in '' 'Storyteller (Writer)')")
b=$(decision model-ask-guard.sh "$(agent_in '' storyteller)")
c=$(decision model-ask-guard.sh "$(agent_in '' plain)")
[ "$a$b$c" = ASKASKok ] && pass || fail "name=$a file=$b plain=$c"

begin_test "SUPERCHARGER_MODEL_ASK_GUARD=0 turns the Agent check off"
[ "$(decision model-ask-guard.sh "$(agent_in fable '')" SUPERCHARGER_MODEL_ASK_GUARD=0)" = ok ] && pass || fail "still asked"

stop_in() { jq -nc --arg p "$1" '{session_id:"st1",hook_event_name:"Stop",transcript_path:$p}'; }
stop_run() { printf '%s' "$(stop_in "$1")" | env HOME="$TEST_HOME" SUPERCHARGER_STATE="$ST" bash "$REPO_DIR/hooks/model-ask-guard.sh" 2>/dev/null; }
TR="$TEST_HOME/t.jsonl"
printf '%s\n' '{"type":"assistant","message":{"model":"claude-opus-5-5","content":[]}}' '{"type":"assistant","message":{"model":"claude-fable-5-2","content":[]}}' > "$TR"
begin_test "Stop: a session answering on Fable is reported to the user"
out=$(stop_run "$TR")
case "$out" in *'"systemMessage"'*claude-fable-5-2*) pass ;; *) fail "got: $out" ;; esac
begin_test "Stop: reported once per session and model"
[ -z "$(stop_run "$TR")" ] && pass || fail "reported twice"
begin_test "Stop: a session on Opus is not reported"
printf '%s\n' '{"type":"assistant","message":{"model":"claude-opus-5-5","content":[]}}' > "$TEST_HOME/t2.jsonl"
out=$(printf '%s' "$(jq -nc --arg p "$TEST_HOME/t2.jsonl" '{session_id:"st2",hook_event_name:"Stop",transcript_path:$p}')" | env HOME="$TEST_HOME" SUPERCHARGER_STATE="$ST" bash "$REPO_DIR/hooks/model-ask-guard.sh" 2>/dev/null)
[ -z "$out" ] && pass || fail "got: $out"

sl() { printf '{"model":{"id":"%s","display_name":"M"},"workspace":{"current_dir":"/tmp"},"session_id":"sl-%s"}' "$1" "$1" | env HOME="$TEST_HOME" SUPERCHARGER_STATE="$ST" bash "$REPO_DIR/hooks/statusline.sh" 2>/dev/null | head -n 1; }
begin_test "statusline warns on a Fable session and not on Opus"
a=$(sl claude-fable-5-2); b=$(sl claude-opus-5-5)
case "$a" in *"fable: switch with /model"*) case "$b" in *switch*) fail "opus warned" ;; *) pass ;; esac ;; *) fail "fable line: $a" ;; esac

begin_test "registration: model-ask-guard on PreToolUse Agent and Stop (lib + plugin)"
grep -q 'PreToolUse|Agent|${hooks_dir}/model-ask-guard.sh' "$REPO_DIR/lib/hooks.sh" \
  && grep -q 'Stop|\*|${hooks_dir}/model-ask-guard.sh' "$REPO_DIR/lib/hooks.sh" \
  && grep -q 'model-ask-guard.sh' "$REPO_DIR/hooks/hooks.json" && pass || fail "not registered"

report
