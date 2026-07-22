#!/usr/bin/env bash
# Tests for redirect-clobber-guard.sh (v2.20.0) — asks before a Bash redirect /
# in-place edit overwrites a git-TRACKED file (bypassing the Write/Edit guards).
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

H="$REPO_DIR/hooks/redirect-clobber-guard.sh"
echo "=== Redirect Clobber Guard Tests ==="

# Hermetic: isolated state + a throwaway git repo with a tracked source file and a
# tracked file inside a generated dir.
_RCG_ST=$(mktemp -d); mkdir -p "$_RCG_ST/scope"
_RCG_R=$(mktemp -d)
git -C "$_RCG_R" init -q
git -C "$_RCG_R" config user.email t@t.co; git -C "$_RCG_R" config user.name t
echo "code" > "$_RCG_R/app.ts"; mkdir -p "$_RCG_R/dist"; echo "gen" > "$_RCG_R/dist/bundle.js"
git -C "$_RCG_R" add -A; git -C "$_RCG_R" commit -qm init 2>/dev/null

# run the hook on CMD in the temp repo; echo ASK or ALLOW. Resets the per-file ack
# each call so the once-per-file dedup doesn't mask independent cases.
rcg() {
  rm -f "$_RCG_ST/scope/.redirect-clobber-ack-rcgs"
  local payload
  payload=$(python3 -c 'import json,sys;print(json.dumps({"tool_name":"Bash","cwd":sys.argv[1],"tool_input":{"command":sys.argv[2]},"session_id":"rcgs"}))' "$_RCG_R" "$1")
  local out
  out=$(printf '%s' "$payload" | SUPERCHARGER_STATE="$_RCG_ST" bash "$H" 2>/dev/null)
  if printf '%s' "$out" | grep -q '"permissionDecision":"ask"'; then echo ASK; else echo ALLOW; fi
}

check() { begin_test "redirect-clobber: $2 → $3"; [ "$(rcg "$1")" = "$3" ] && pass || fail "expected $3 for: $1"; }

check 'echo hacked > app.ts'          "truncate redirect over tracked source"   ASK
check "sed -i 's/code/x/' app.ts"     "sed -i over tracked source"              ASK
check 'cat other | tee app.ts'        "tee (no -a) over tracked source"         ASK
check 'echo x >> app.ts'              "append (>>) never fires"                 ALLOW
check 'cat other | tee -a app.ts'     "tee -a (append)"                          ALLOW
check 'echo x > newfile.ts'           "untracked file"                          ALLOW
check 'echo x > /tmp/scratch.txt'     "outside-repo path"                       ALLOW
check 'echo x > dist/bundle.js'       "tracked but generated dir (excluded)"    ALLOW
check 'grep foo app.ts > /tmp/out'    "redirect to untracked target"            ALLOW
check 'ls -la app.ts'                 "no clobber op"                            ALLOW
# v2.22.10: fd-qualified truncate + clobber-force
check 'echo x 1> app.ts'              "fd-qualified truncate 1>"                 ASK
check 'echo x >| app.ts'              "clobber-force >|"                         ASK
check 'echo x >> app.ts'              "append >> (not a truncate)"               ALLOW
check 'make 2>&1 | tee build.log'     "2>&1 fd-dup (not a truncate of app.ts)"   ALLOW

# once-per-file dedup: same file twice (no reset) → 2nd silent
begin_test "redirect-clobber: asks once per file per session"
rm -f "$_RCG_ST/scope/.redirect-clobber-ack-rcgs"
_P=$(python3 -c 'import json,sys;print(json.dumps({"tool_name":"Bash","cwd":sys.argv[1],"tool_input":{"command":"echo x > app.ts"},"session_id":"rcgs"}))' "$_RCG_R")
_A=$(printf '%s' "$_P" | SUPERCHARGER_STATE="$_RCG_ST" bash "$H" 2>/dev/null | grep -c '"ask"')
_B=$(printf '%s' "$_P" | SUPERCHARGER_STATE="$_RCG_ST" bash "$H" 2>/dev/null | grep -c '"ask"')
{ [ "$_A" -ge 1 ] && [ "$_B" -eq 0 ]; } && pass || fail "expected first=ask second=silent (got $_A/$_B)"

# kill switch
begin_test "redirect-clobber: SUPERCHARGER_REDIRECT_CLOBBER_GUARD=0 disables it"
rm -f "$_RCG_ST/scope/.redirect-clobber-ack-rcgs"
_P=$(python3 -c 'import json,sys;print(json.dumps({"tool_name":"Bash","cwd":sys.argv[1],"tool_input":{"command":"echo x > app.ts"},"session_id":"rcgs"}))' "$_RCG_R")
_O=$(printf '%s' "$_P" | SUPERCHARGER_STATE="$_RCG_ST" SUPERCHARGER_REDIRECT_CLOBBER_GUARD=0 bash "$H" 2>/dev/null)
[ -z "$_O" ] && pass || fail "kill switch did not disable it: $_O"

rm -rf "$_RCG_ST" "$_RCG_R"
report
