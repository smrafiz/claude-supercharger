#!/usr/bin/env bash
# Per-agent allowlists (agent-allowlist-guard.sh): an agent definition's
# `supercharger-allow:` frontmatter narrows its Bash / WebFetch / Write calls.
# Payloads follow the documented shape: a subagent's tool event carries
# agent_id + agent_type (code.claude.com/docs/en/hooks, common input fields).
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

HOOK="$REPO_DIR/hooks/agent-allowlist-guard.sh"
echo "=== Per-Agent Allowlist Guard Tests ==="

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
H="$T/home"; P="$T/proj"
mkdir -p "$H/.claude/agents" "$P/.git" "$P/src" "$P/.claude/agents"
NP=$(native_path "$P")

cat > "$H/.claude/agents/narrow.md" <<'EOF'
---
name: narrow
description: fixture agent with all three lists
supercharger-allow:
  bash: ["git status", "git diff*", "npm test"]   # comment
  webfetch: [docs.python.org, "*.github.com"]
  write:
    - src/**
    - tests/**
---
Body text.
EOF

# Frontmatter name differs from the filename: agent_type is the name.
cat > "$H/.claude/agents/code-helper.md" <<'EOF'
---
name: Tony Stark (Engineer)
supercharger-allow:
  webfetch: ["example.org"]
---
EOF

cat > "$H/.claude/agents/plain.md" <<'EOF'
---
name: plain
description: no list at all
---
EOF

cat > "$H/.claude/agents/broken.md" <<'EOF'
---
name: broken
supercharger-allow:
  bash: ["git status", "unterminated]
---
EOF

# Project definition shadows the user one of the same name.
cat > "$H/.claude/agents/shadowed.md" <<'EOF'
---
name: shadowed
supercharger-allow:
  bash: ["ls"]
---
EOF
cat > "$P/.claude/agents/shadowed.md" <<'EOF'
---
name: shadowed
description: project copy, no list
---
EOF

# Sets OUT / ERR / RC in the caller (no command substitution around the call).
run() { # agent tool input-json [with_agent_id=1]
  local id='"agent_id":"a-1",'
  [ "${4:-1}" = 0 ] && id=""
  printf '{%s"agent_type":"%s","cwd":"%s","tool_name":"%s","tool_input":%s}' "$id" "$1" "$NP" "$2" "$3" \
    | HOME="$H" SUPERCHARGER_STATE="$T/state" CLAUDE_PROJECT_DIR="" bash "$HOOK" >"$T/out" 2>"$T/err"
  RC=$?; OUT=$(cat "$T/out"); ERR=$(cat "$T/err")
}
allowed() { [ "$RC" -eq 0 ] && [ -z "$OUT" ] && pass || fail "expected allow, rc=$RC out=$OUT err=$ERR"; }
denied() {
  if [ "$RC" -eq 2 ] && printf '%s' "$OUT" | grep -q '"permissionDecision":"deny"'; then
    if [ -n "${1:-}" ] && ! printf '%s' "$OUT" | grep -qF -- "$1"; then fail "deny lacks '$1': $OUT"; else pass; fi
  else fail "expected deny, rc=$RC out=$OUT"; fi
}
cmd() { printf '{"command":"%s"}' "$1"; }

begin_test "no list declared: any Bash allowed"
run plain Bash "$(cmd 'curl https://example.com')"; allowed
begin_test "agent with a webfetch list only: Bash untouched"
run "Tony Stark (Engineer)" Bash "$(cmd 'curl https://example.com')"; allowed
begin_test "unknown agent: allowed"
run nobody Bash "$(cmd 'curl https://example.com')"; allowed

begin_test "bash: exact prefix allowed"
run narrow Bash "$(cmd 'git status')"; allowed
begin_test "bash: prefix plus arguments allowed"
run narrow Bash "$(cmd 'git status --short')"; allowed
begin_test "bash: glob entry allowed, with 2>&1 and a compound of allowed parts"
run narrow Bash "$(cmd 'git diff --stat 2>&1 && npm test >/dev/null')"; allowed
begin_test "bash: out-of-list command denied, reason names agent and list"
run narrow Bash "$(cmd 'curl https://example.com')"; denied "subagent 'narrow'"
begin_test "bash: deny names the definition file and the list"
printf '%s' "$OUT" | grep -q 'narrow.md' && printf '%s' "$OUT" | grep -q 'supercharger-allow.bash' && pass || fail "$OUT"
begin_test "bash: prefix is word-bounded (git statusx is not git status)"
run narrow Bash "$(cmd 'git statusx')"; denied
begin_test "bash: compound with one disallowed segment denied"
run narrow Bash "$(cmd 'git status && curl https://example.com')"; denied "curl"
begin_test "bash: pipe into a disallowed command denied"
run narrow Bash "$(cmd 'git diff | tee out.txt')"; denied "tee"
begin_test "bash: newline-separated second command denied"
run narrow Bash '{"command":"git status\nrm -f notes.txt"}'; denied "rm -f"
begin_test "bash: wrapper and env prefix normalised (env X=1 sudo curl -> curl)"
run narrow Bash "$(cmd 'env X=1 sudo curl https://example.com')"; denied "curl"
begin_test "bash: wrapper around an allowed command still allowed"
run narrow Bash "$(cmd 'env GIT_PAGER=cat git status')"; allowed
begin_test "bash: command substitution refused"
run narrow Bash "$(cmd 'git status $(rm -f x)')"; denied "substitution"
begin_test "bash: backticks refused"
run narrow Bash '{"command":"git status `id`"}'; denied "backticks"
begin_test "bash: output redirect refused"
run narrow Bash "$(cmd 'git diff > /tmp/x.patch')"; denied "redirect"
begin_test "bash: > inside quotes is not a redirect"
run narrow Bash '{"command":"git diff \"a>b\""}'; allowed
begin_test "bash: Monitor carries the bash list"
run narrow Monitor "$(cmd 'curl https://example.com')"; denied

begin_test "webfetch: listed host allowed"
run narrow WebFetch '{"url":"https://docs.python.org/3/library/re.html"}'; allowed
begin_test "webfetch: subdomain glob, case, port and userinfo stripped"
run narrow WebFetch '{"url":"https://someone@API.GitHub.com:443/repos"}'; allowed
begin_test "webfetch: listed name in the PATH of another host denied"
run narrow WebFetch '{"url":"https://evil.example/docs.python.org"}'; denied "evil.example"
begin_test "webfetch: lookalike suffix denied (docs.python.org.evil.example)"
run narrow WebFetch '{"url":"https://docs.python.org.evil.example/"}'; denied
begin_test "webfetch: *.github.com does not match github.com.evil.example"
run narrow WebFetch '{"url":"https://api.github.com.evil.example/"}'; denied
begin_test "webfetch: non-http scheme denied"
run narrow WebFetch '{"url":"file:///etc/hosts"}'; denied
begin_test "webfetch: frontmatter name differing from filename is resolved"
run "Tony Stark (Engineer)" WebFetch '{"url":"https://other.example/"}'; denied "Tony Stark"

begin_test "write: in-list relative path allowed"
run narrow Write '{"file_path":"src/app.py","content":"x"}'; allowed
begin_test "write: in-list absolute path allowed"
run narrow Edit "$(printf '{"file_path":"%s/src/app.py"}' "$NP")"; allowed
begin_test "write: out-of-list path denied"
run narrow Write '{"file_path":"README.md","content":"x"}'; denied "README.md"
begin_test "write: traversal src/../../etc denied"
run narrow Write '{"file_path":"src/../../etc/hosts","content":"x"}'; denied
begin_test "write: traversal that stays outside the list (src/../README.md) denied"
run narrow MultiEdit '{"file_path":"src/../README.md","edits":[]}'; denied
begin_test "write: symlink inside src pointing outside denied"
mkdir -p "$T/outside"; ln -s "$T/outside" "$P/src/link" 2>/dev/null
if [ -L "$P/src/link" ]; then
  run narrow Write '{"file_path":"src/link/x.txt","content":"x"}'; denied
else pass; fi
begin_test "write: NotebookEdit notebook_path checked"
run narrow NotebookEdit '{"notebook_path":"notes/a.ipynb","new_source":"x"}'; denied
begin_test "write: an agent may not edit its own definition"
run plain Write "$(printf '{"file_path":"%s"}' "$(native_path "$H/.claude/agents/plain.md")")"; allowed
run "Tony Stark (Engineer)" Edit "$(printf '{"file_path":"%s"}' "$(native_path "$H/.claude/agents/code-helper.md")")"; denied "own definition"
begin_test "write: ~/ path normalised like sc_norm_path"
run narrow Write '{"file_path":"~/elsewhere.txt","content":"x"}'; denied "elsewhere.txt"

begin_test "nested Agent spawn from a listed agent denied"
run narrow Agent '{"subagent_type":"general-purpose","prompt":"x"}'; denied "nested"
begin_test "nested Agent spawn from an unlisted agent allowed"
run plain Agent '{"subagent_type":"general-purpose","prompt":"x"}'; allowed

begin_test "main session (no agent_id) is unaffected even with agent_type set"
run narrow Bash "$(cmd 'curl https://example.com')" 0; allowed
begin_test "main session Write outside any list unaffected"
run narrow Write '{"file_path":"/etc/hosts","content":"x"}' 0; allowed

begin_test "project definition shadows the user one (project has no list)"
run shadowed Bash "$(cmd 'curl https://example.com')"; allowed

begin_test "malformed frontmatter fails open"
run broken Bash "$(cmd 'curl https://example.com')"; allowed
begin_test "malformed frontmatter leaves a stderr note"
printf '%s' "$ERR" | grep -q 'agent-allowlist-guard' && printf '%s' "$ERR" | grep -q 'failing open' && pass || fail "stderr: $ERR"

begin_test "kill switch SUPERCHARGER_AGENT_ALLOWLIST=0"
printf '{"agent_id":"a","agent_type":"narrow","cwd":"%s","tool_name":"Bash","tool_input":{"command":"curl x"}}' "$NP" \
  | HOME="$H" SUPERCHARGER_AGENT_ALLOWLIST=0 bash "$HOOK" >/dev/null 2>&1 && pass || fail "rc=$?"

begin_test "no definitions declare a list: exits before python"
H2="$T/home2"; mkdir -p "$H2/.claude/agents"; cp "$H/.claude/agents/plain.md" "$H2/.claude/agents/"
# python3 replaced by a shim that fails loudly: a call reaching it would show.
mkdir -p "$T/shim"; printf '#!/bin/sh\necho CALLED >&2; exit 9\n' > "$T/shim/python3"; chmod +x "$T/shim/python3"
R=$(printf '{"agent_id":"a","agent_type":"plain","cwd":"/nonexistent","tool_name":"Bash","tool_input":{"command":"curl x"}}' \
  | HOME="$H2" PATH="$T/shim:$PATH" bash "$HOOK" 2>&1); RC=$?
[ "$RC" -eq 0 ] && [ -z "$R" ] && pass || fail "rc=$RC out=$R"

# Native Windows python writes newlines as CRLF: every list entry but the last came
# back as `git status<CR>` and nothing matched (Windows CI, 8 of 47 failed). Build those
# bytes here with a python3 shim, so macOS and Linux exercise the Windows path.
begin_test "CRLF detector output (native Windows python): allowed entry still allowed"
REALPY=$(command -v python3); mkdir -p "$T/crlf"
printf '#!/bin/sh\n"%s" "$@" | sed "s/$/\\r/"\n' "$REALPY" > "$T/crlf/python3"; chmod +x "$T/crlf/python3"
OLDPATH="$PATH"; PATH="$T/crlf:$PATH"
run narrow Bash "$(cmd 'git status')"; PATH="$OLDPATH"; allowed
begin_test "registered in lib/hooks.sh and hooks.json"
grep -q 'agent-allowlist-guard.sh' "$REPO_DIR/lib/hooks.sh" && grep -q 'agent-allowlist-guard' "$REPO_DIR/hooks/hooks.json" \
  && pass || fail "not registered"
begin_test "hook and resolver are executable"
[ -x "$HOOK" ] && [ -x "$REPO_DIR/hooks/agent-allowlist-detect.py" ] && pass || fail "mode 644"

report
