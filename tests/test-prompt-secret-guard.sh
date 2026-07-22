#!/usr/bin/env bash
# Suite for hooks/prompt-secret-guard.sh (UserPromptSubmit — blocks a live
# credential pasted into the prompt before it reaches the model + transcript).
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

H="$REPO_DIR/hooks/prompt-secret-guard.sh"

# Credential-shaped strings assembled from fragments so this test file carries no
# literal secret pattern (which would otherwise trip the Write content scanner and
# the commit/output secret guards on the file itself).
AK="AK""IA""1234567890ABCDEF"
GH="gh""p_""0123456789abcdefghij0123456789abcdef"
SK="sk""-""0123456789abcdefghij0123456789"
PK="PRIV""ATE KEY"; BEG="-----BE""GIN RSA $PK-----"

# exit code for a given prompt string (2 = block)
rc_for() {
  local j; j=$(printf '{"prompt":%s,"session_id":"t"}' "$(python3 -c 'import json,sys;print(json.dumps(sys.argv[1]))' "$1")")
  printf '%s' "$j" | bash "$H" >/dev/null 2>&1; echo $?
}
block_case() { begin_test "prompt-secret-guard: blocks $1"; [ "$(rc_for "$2")" -eq 2 ] && pass || fail "expected block for: $1"; }
allow_case() { begin_test "prompt-secret-guard: allows $1"; [ "$(rc_for "$2")" -eq 0 ] && pass || fail "expected allow for: $1"; }

# ---- live credentials pasted into the prompt → BLOCK ----
block_case "AWS access key"      "please use my key $AK for the deploy"
block_case "GitHub token"        "here is the token $GH"
block_case "OpenAI api key"      "export OPENAI_API_KEY=$SK"
block_case "private key header"  "$BEG"

# ---- benign prompts → ALLOW (no false positive) ----
allow_case "Bearer authentication phrase" "add Bearer authentication to the API"
allow_case "Bearer token phrase"          "the request needs a Bearer token header"
allow_case "generic api key mention"      "where should I store my api key safely"
allow_case "ordinary coding request"      "refactor the login function to be async"

# ---- override + disable escape hatches ----
begin_test "prompt-secret-guard: SUPERCHARGER_ALLOW_PROMPT_SECRETS=1 overrides the block"
j=$(printf '{"prompt":%s,"session_id":"t"}' "$(python3 -c 'import json,sys;print(json.dumps(sys.argv[1]))' "key $AK")")
SUPERCHARGER_ALLOW_PROMPT_SECRETS=1 bash "$H" >/dev/null 2>&1 <<<"$j"
[ "$?" -eq 0 ] && pass || fail "override env var did not allow the prompt"

begin_test "prompt-secret-guard: SUPERCHARGER_PROMPT_SECRET_GUARD=0 disables the hook"
SUPERCHARGER_PROMPT_SECRET_GUARD=0 bash "$H" >/dev/null 2>&1 <<<"$j"
[ "$?" -eq 0 ] && pass || fail "disable env var did not bypass the hook"

# ---- fail-open on malformed / empty input ----
begin_test "prompt-secret-guard: empty prompt exits cleanly"
printf '{"prompt":"","session_id":"t"}' | bash "$H" >/dev/null 2>&1
[ "$?" -eq 0 ] && pass || fail "empty prompt did not exit 0"

begin_test "prompt-secret-guard: malformed JSON exits cleanly"
printf 'not json {' | bash "$H" >/dev/null 2>&1
[ "$?" -eq 0 ] && pass || fail "malformed input did not exit 0"

# ---- 2.21.5: fail OPEN when the pattern lib is unavailable (not fail-closed) ----
begin_test "prompt-secret-guard: missing pattern lib → fails OPEN (exit 0), never blocks every prompt"
TMPH=$(mktemp -d)
cp "$H" "$TMPH/prompt-secret-guard.sh"   # copy hook WITHOUT its lib-secret-patterns.sh sibling
printf '{"prompt":"hello world","session_id":"t"}' | bash "$TMPH/prompt-secret-guard.sh" >/dev/null 2>&1
[ "$?" -eq 0 ] && pass || fail "missing lib blocked the prompt (fail-closed regression)"
rm -rf "$TMPH"

report
