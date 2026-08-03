#!/usr/bin/env bash
# Advisory nudges survive going async, and _json_get honours top-level semantics (v2.26.38)
#
# Two things this file holds, both from the same question: "is the speed worth it,
# and does anything get lost?"
#
# 1. prompt-validator moved to async in v2.26.37 (35ms off the prompt path). Its
#    stderr note can now land beside or after the answer instead of before it.
#    The note is therefore PERSISTED as well, so /why can show it later. Note that
#    a nudge was already losable when the hook was synchronous — scrolled past, it
#    was gone. Recording it is a net improvement, not a consolation.
#
# 2. _json_get replaced a jq fork in seven hooks. The underlying reader matches a
#    key at ANY depth (deliberate — safety.sh needs that for tool_input.command),
#    but these callers want TOP-LEVEL fields and their jq filters say so. Without
#    a depth check the two disagreed on a payload whose only `cwd` was nested.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

echo "=== Prompt-Note Durability + JSON Depth Tests ==="

# --- 1. the nudge is not lost -----------------------------------------------
run_pv() { # prompt, state_dir, sid -> stderr
  printf '%s' "$(V="$1" python3 -c '
import json, os
print(json.dumps({"prompt": os.environ["V"]}))')" \
    | SUPERCHARGER_STATE="$2" CLAUDE_CODE_SESSION_ID="$3" \
      bash "$REPO_DIR/hooks/prompt-validator.sh" 2>&1 >/dev/null
}

ST=$(mktemp -d); mkdir -p "$ST/scope"

begin_test "a triggering prompt still emits its note on stderr"
run_pv 'fix all the things' "$ST" sid1 | grep -q 'Supercharger' && pass || fail "note lost"

begin_test "and the note is persisted for /why"
NF="$ST/scope/.prompt-notes-sid1"
[ -s "$NF" ] && grep -q 'All' "$NF" && pass || fail "not recorded: $(ls -A "$ST/scope" | tr '\n' ' ')"

begin_test "the record carries a timestamp so /why can order it"
grep -qE '^\[[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}\] ' "$NF" && pass || fail "no timestamp: $(head -1 "$NF")"

begin_test "notes are per-session, not shared across sessions"
run_pv 'fix all the things' "$ST" sid2 >/dev/null
[ -s "$ST/scope/.prompt-notes-sid2" ] && [ "$(wc -l < "$NF" | tr -d ' ')" = "1" ] && pass \
  || fail "sessions bled into one file"

begin_test "a prompt with no anti-pattern writes nothing"
ST2=$(mktemp -d); mkdir -p "$ST2/scope"
run_pv 'yes' "$ST2" sid1 >/dev/null
[ "$(ls -A "$ST2/scope" 2>/dev/null | wc -l | tr -d ' ')" = "0" ] && pass || fail "wrote a file with no notes"
rm -rf "$ST2"

begin_test "the note file is bounded (it appends on every triggering prompt)"
python3 -c "
import os
p = '$NF'
open(p, 'w').write('\n'.join('[2026-01-01 00:00] note %d' % i for i in range(400)) + '\n')"
run_pv 'fix all the things' "$ST" sid1 >/dev/null
N=$(wc -l < "$NF" | tr -d ' ')
[ "$N" -le 200 ] && pass || fail "grew to $N lines unbounded"

begin_test "persistence failure never costs the stderr note"
# Read-only scope dir: the note must still reach stderr.
ST3=$(mktemp -d); mkdir -p "$ST3/scope"; chmod 500 "$ST3/scope"
run_pv 'fix all the things' "$ST3" sid1 | grep -q 'Supercharger' && pass || fail "advice lost when the file was unwritable"
chmod 700 "$ST3/scope"; rm -rf "$ST3"

begin_test "/why knows where to look"
grep -q 'prompt-notes' "$REPO_DIR/configs/commands/why.md" && pass || fail "why.md does not read the notes file"

begin_test "the generated command carries it too (commands/ is generated)"
grep -q 'prompt-notes' "$REPO_DIR/commands/why.md" && pass \
  || fail "run tools/gen-plugin-commands.sh — the config and the generated copy have drifted"
rm -rf "$ST"

# --- 2. _json_get depth semantics -------------------------------------------
jget() { # payload -> resolved cwd
  local td; td=$(mktemp -d)
  cat > "$td/t.sh" <<'EOF'
. hooks/lib-json-fast.sh
IFS= read -r -d '' _INPUT || true
C=""; _json_get C cwd "$_INPUT" '.cwd // .workspace.current_dir // empty'
printf '%s' "$C"
EOF
  local out; out=$(cd "$REPO_DIR" && printf '%s' "$1" | bash "$td/t.sh")
  rm -rf "$td"; printf '%s' "$out"
}

begin_test "a top-level key resolves via the fast path"
[ "$(jget '{"cwd":"/top","prompt":"x"}')" = "/top" ] && pass || fail "got $(jget '{"cwd":"/top","prompt":"x"}')"

begin_test "a NESTED-only key does not shadow the jq semantics"
P='{"other":{"cwd":"/nested"},"workspace":{"current_dir":"/correct"},"prompt":"x"}'
GOT=$(jget "$P"); WANT=$(printf '%s' "$P" | jq -r '.cwd // .workspace.current_dir // empty')
[ "$GOT" = "$WANT" ] && pass || fail "fast path said '$GOT', jq says '$WANT'"

begin_test "the workspace fallback still works"
[ "$(jget '{"workspace":{"current_dir":"/ws"},"prompt":"x"}')" = "/ws" ] && pass || fail "fallback broken"

begin_test "an absent key yields empty, not a stale value"
[ -z "$(jget '{"prompt":"x"}')" ] && pass || fail "got a value for an absent key"

report
