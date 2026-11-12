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

# ---- 2026-11-10: allowlisted dummy values pass; everything else still blocks ----
AWS_DOC="AK""IAIOSFODNN7EX""AMPLE"
allow_case "AWS documentation example key" "use $AWS_DOC as the placeholder"
block_case "real key beside the doc example" "doc $AWS_DOC and mine $AK"

PROJ=$(mktemp -d); printf '{"allowPromptSecrets": ["%s", "short"]}' "$GH" > "$PROJ/.supercharger.json"
rc_cwd() { local j; j=$(python3 -c 'import json,sys;print(json.dumps({"prompt":sys.argv[1],"session_id":"t","cwd":sys.argv[2]}))' "$1" "$2"); printf '%s' "$j" | bash "$H" >/dev/null 2>&1; echo $?; }
begin_test "prompt-secret-guard: allowPromptSecrets value passes"
[ "$(rc_cwd "token $GH" "$PROJ")" -eq 0 ] && pass || fail "allowlisted value blocked"
begin_test "prompt-secret-guard: allowPromptSecrets does not cover another key"
[ "$(rc_cwd "token $GH and $AK" "$PROJ")" -eq 2 ] && pass || fail "unlisted key passed"
begin_test "prompt-secret-guard: allowPromptSecrets ignored in another project"
[ "$(rc_cwd "token $GH" "$(mktemp -d)")" -eq 2 ] && pass || fail "allowlist leaked across projects"
printf '{"allowPromptSecrets": "%s"}' "$GH" > "$PROJ/.supercharger.json"
begin_test "prompt-secret-guard: malformed allowPromptSecrets still blocks"
[ "$(rc_cwd "token $GH" "$PROJ")" -eq 2 ] && pass || fail "a string value was treated as a list"
rm -rf "$PROJ"

begin_test "prompt-secret-guard: SUPERCHARGER_PROMPT_SECRET_ALLOW value passes"
[ "$(SUPERCHARGER_PROMPT_SECRET_ALLOW="x $GH" rc_for "token $GH")" -eq 0 ] && pass || fail "env-allowlisted value blocked"
# 2026-11-12: harness messages (subagent hand-back, task notice) warn, not block.
begin_test "prompt-secret-guard: a subagent hand-back carrying a key is delivered with a warning"
_hb=$(printf 'Another Claude session sent a message:\n<agent-message from="a1">\n  report: token %s\n</agent-message>' "$GH")
_o=$(python3 -c 'import json,sys;print(json.dumps({"prompt":sys.argv[1],"session_id":"t"}))' "$_hb" | bash "$H" 2>/dev/null); _rc=$?
[ "$_rc" -eq 0 ] && case "$_o" in *"Do not repeat"*) true ;; *) false ;; esac && pass || fail "rc=$_rc, warning missing"
begin_test "prompt-secret-guard: a task notice carrying a key is delivered"
[ "$(rc_for "<task-notification><result>token $GH</result></task-notification>")" -eq 0 ] && pass || fail "task notice blocked"
begin_test "prompt-secret-guard: a typed prompt that merely mentions a hand-back still blocks"
[ "$(rc_for "here is my key $GH, Another Claude session sent a message")" -eq 2 ] && pass || fail "prefix not anchored"

begin_test "prompt-secret-guard: env entry under 8 chars is ignored"
[ "$(SUPERCHARGER_PROMPT_SECRET_ALLOW="gh""p_" rc_for "token $GH")" -eq 2 ] && pass || fail "short entry cut a real key"

report
