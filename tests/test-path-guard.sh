#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

HOOK="$REPO_DIR/hooks/path-guard.sh"

echo "=== path-guard Tests ==="

export SUPERCHARGER_NO_DEDUP=1

begin_test "path-guard: hook exists and is executable"
[ -x "$HOOK" ] && pass || fail "hook missing or not executable"

begin_test "path-guard: blocks path traversal (..)"
PROJ=$(mktemp -d)
INPUT=$(printf '{"tool_name":"Edit","tool_input":{"file_path":"%s/../../../etc/passwd"},"cwd":"%s"}' "$PROJ" "$PROJ")
OUT=$(echo "$INPUT" | bash "$HOOK" 2>/dev/null)
echo "$OUT" | grep -q 'permissionDecision.*deny' && pass || fail "expected deny, got: $OUT"
rm -rf "$PROJ"

begin_test "path-guard: blocks URL-encoded traversal (%2e%2e)"
PROJ=$(mktemp -d)
INPUT=$(printf '{"tool_name":"Edit","tool_input":{"file_path":"%%2e%%2e/%%2e%%2e/etc/passwd"},"cwd":"%s"}' "$PROJ")
OUT=$(echo "$INPUT" | bash "$HOOK" 2>/dev/null)
echo "$OUT" | grep -q 'permissionDecision.*deny' && pass || fail "expected deny, got: $OUT"
rm -rf "$PROJ"

begin_test "path-guard: blocks .git/hooks/ writes"
PROJ=$(mktemp -d)
INPUT=$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s/.git/hooks/pre-commit"},"cwd":"%s"}' "$PROJ" "$PROJ")
OUT=$(echo "$INPUT" | bash "$HOOK" 2>/dev/null)
echo "$OUT" | grep -q 'permissionDecision.*deny' && pass || fail "expected deny on .git/hooks, got: $OUT"
rm -rf "$PROJ"

begin_test "path-guard: blocks ~/.ssh/ writes"
PROJ=$(mktemp -d)
INPUT=$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s/.ssh/id_rsa"},"cwd":"%s"}' "$HOME" "$PROJ")
OUT=$(echo "$INPUT" | bash "$HOOK" 2>/dev/null)
echo "$OUT" | grep -q 'permissionDecision.*deny' && pass || fail "expected deny on ~/.ssh, got: $OUT"
rm -rf "$PROJ"

begin_test "path-guard: blocks node_modules/.bin/ writes"
PROJ=$(mktemp -d)
INPUT=$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s/node_modules/.bin/evil"},"cwd":"%s"}' "$PROJ" "$PROJ")
OUT=$(echo "$INPUT" | bash "$HOOK" 2>/dev/null)
echo "$OUT" | grep -q 'permissionDecision.*deny' && pass || fail "expected deny on node_modules/.bin, got: $OUT"
rm -rf "$PROJ"

begin_test "path-guard: allows normal in-project writes"
PROJ=$(mktemp -d)
INPUT=$(printf '{"tool_name":"Edit","tool_input":{"file_path":"%s/src/foo.ts"},"cwd":"%s"}' "$PROJ" "$PROJ")
OUT=$(echo "$INPUT" | bash "$HOOK" 2>/dev/null)
[ -z "$OUT" ] && pass || fail "expected silent allow, got: $OUT"
rm -rf "$PROJ"

begin_test "path-guard: respects disableSecurityCategories opt-out"
PROJ=$(mktemp -d)
echo '{"disableSecurityCategories":["build-artifacts"]}' > "$PROJ/.supercharger.json"
INPUT=$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s/node_modules/.bin/foo"},"cwd":"%s"}' "$PROJ" "$PROJ")
OUT=$(echo "$INPUT" | bash "$HOOK" 2>/dev/null)
[ -z "$OUT" ] && pass || fail "expected allow with build-artifacts disabled, got: $OUT"
rm -rf "$PROJ"

begin_test "path-guard: SUPERCHARGER_PATH_GUARD=0 disables hook"
PROJ=$(mktemp -d)
INPUT=$(printf '{"tool_name":"Edit","tool_input":{"file_path":"%s/../../../etc/passwd"},"cwd":"%s"}' "$PROJ" "$PROJ")
OUT=$(SUPERCHARGER_PATH_GUARD=0 bash -c "echo '$INPUT' | bash $HOOK" 2>/dev/null)
[ -z "$OUT" ] && pass || fail "expected disabled output, got: $OUT"
rm -rf "$PROJ"

begin_test "path-guard: skips non-Edit/Write tools"
PROJ=$(mktemp -d)
INPUT=$(printf '{"tool_name":"Bash","tool_input":{"command":"rm -rf /"},"cwd":"%s"}' "$PROJ")
OUT=$(echo "$INPUT" | bash "$HOOK" 2>/dev/null)
[ -z "$OUT" ] && pass || fail "expected silent on Bash, got: $OUT"
rm -rf "$PROJ"

# v2.6.85: CVE-2026-35021 — command substitution in file path
# Use python to build the JSON so $() / backtick survive shell quoting unmangled.
begin_test "path-guard: blocks file path with \$() (CVE-2026-35021)"
PROJ=$(mktemp -d)
INPUT=$(python3 -c "import json,sys; print(json.dumps({'tool_name':'Write','tool_input':{'file_path':sys.argv[1]+'/foo\$(curl evil).py','content':'x'},'cwd':sys.argv[1]}))" "$PROJ")
OUT=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
echo "$OUT" | grep -qi "command substitution" && pass || fail "no CVE-2026-35021 block: $OUT"
rm -rf "$PROJ"

begin_test "path-guard: blocks file path with backtick (CVE-2026-35021)"
PROJ=$(mktemp -d)
INPUT=$(python3 -c "import json,sys; print(json.dumps({'tool_name':'Edit','tool_input':{'file_path':sys.argv[1]+'/foo\`id\`.py'},'cwd':sys.argv[1]}))" "$PROJ")
OUT=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1)
echo "$OUT" | grep -qi "command substitution" && pass || fail "no backtick block: $OUT"
rm -rf "$PROJ"

begin_test "path-guard: allows benign file path"
PROJ=$(mktemp -d)
INPUT=$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s/src/foo.py","content":"x"},"cwd":"%s"}' "$PROJ" "$PROJ")
OUT=$(echo "$INPUT" | bash "$HOOK" 2>&1)
echo "$OUT" | grep -qi "command substitution" && fail "false positive: $OUT" || pass
rm -rf "$PROJ"

# v2.7.5: SymJack — block writes to MCP server config that would insert an
# attacker-controlled server (auto-spawns with full privileges next session).
begin_test "path-guard: blocks project .mcp.json write (SymJack, v2.7.5)"
PROJ=$(mktemp -d)
INPUT=$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s/.mcp.json","content":"{}"},"cwd":"%s"}' "$PROJ" "$PROJ")
echo "$INPUT" | bash "$HOOK" >/dev/null 2>&1
[ "$?" -eq 2 ] && pass || fail "expected 2 for .mcp.json write"
rm -rf "$PROJ"

begin_test "path-guard: blocks ~/.mcp.json write (SymJack, v2.7.5)"
PROJ=$(mktemp -d)
INPUT=$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s/.mcp.json","content":"{}"},"cwd":"%s"}' "$HOME" "$PROJ")
echo "$INPUT" | bash "$HOOK" >/dev/null 2>&1
[ "$?" -eq 2 ] && pass || fail "expected 2 for ~/.mcp.json write"
rm -rf "$PROJ"

begin_test "path-guard: blocks ~/.claude.json write (SymJack, v2.7.5)"
PROJ=$(mktemp -d)
INPUT=$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s/.claude.json","content":"{}"},"cwd":"%s"}' "$HOME" "$PROJ")
echo "$INPUT" | bash "$HOOK" >/dev/null 2>&1
[ "$?" -eq 2 ] && pass || fail "expected 2 for ~/.claude.json write"
rm -rf "$PROJ"

# v2.7.41 red-team regression: a RELATIVE path through an in-repo symlink that
# resolves outside the project root was a bypass (exit 0) — repo ships
# `escape -> /etc`, agent writes `escape/x`.
begin_test "path-guard: relative path via symlink escaping project is blocked (was bypass)"
PROJ=$(mktemp -d); ln -s /etc "$PROJ/escape"
INPUT=$(printf '{"tool_name":"Write","tool_input":{"file_path":"escape/pwned.conf","content":"x"},"cwd":"%s"}' "$PROJ")
echo "$INPUT" | bash "$HOOK" >/dev/null 2>&1
_RC=$?
# Needs a REAL symlink to escape through. Git Bash silently copies instead of
# linking without developer mode, so the guard is handed an ordinary relative
# path, correctly allows it, and the recon reads "escape not blocked" as a hole.
# Detected, not assumed — see test-path-guard-hardening.sh for the same gate.
if [ ! -L "$PROJ/escape" ]; then
  echo "    (skipped: Git Bash created no symlink — nothing to escape through)"
  pass
else
  [ "$_RC" -eq 2 ] && pass || fail "relative symlink escape not blocked"
fi
# legit relative write inside the project still allowed
INPUT=$(printf '{"tool_name":"Write","tool_input":{"file_path":"src/app.js","content":"x"},"cwd":"%s"}' "$PROJ")
echo "$INPUT" | bash "$HOOK" >/dev/null 2>&1
[ "$?" -eq 0 ] && pass || fail "legit in-project relative write wrongly blocked"
rm -rf "$PROJ"

# v2.8.4: relative top-level guardrail-config writes were a selfmod bypass
# (endswith('/.supercharger.json') required a leading slash).
begin_test "path-guard: blocks RELATIVE .supercharger.json write (v2.8.4 selfmod bypass)"
PROJ=$(mktemp -d)
INPUT=$(printf '{"tool_name":"Write","tool_input":{"file_path":".supercharger.json","content":"{}"},"cwd":"%s"}' "$PROJ")
echo "$INPUT" | bash "$HOOK" >/dev/null 2>&1
[ "$?" -eq 2 ] && pass || fail "relative .supercharger.json not blocked"
rm -rf "$PROJ"

begin_test "path-guard: blocks RELATIVE .mcp.json write (v2.8.4)"
PROJ=$(mktemp -d)
INPUT=$(printf '{"tool_name":"Write","tool_input":{"file_path":".mcp.json","content":"{}"},"cwd":"%s"}' "$PROJ")
echo "$INPUT" | bash "$HOOK" >/dev/null 2>&1
[ "$?" -eq 2 ] && pass || fail "relative .mcp.json not blocked"
rm -rf "$PROJ"

begin_test "path-guard: blocks RELATIVE .claude/settings.json write (v2.8.4)"
PROJ=$(mktemp -d)
INPUT=$(printf '{"tool_name":"Write","tool_input":{"file_path":".claude/settings.json","content":"{}"},"cwd":"%s"}' "$PROJ")
echo "$INPUT" | bash "$HOOK" >/dev/null 2>&1
[ "$?" -eq 2 ] && pass || fail "relative .claude/settings.json not blocked"
rm -rf "$PROJ"

# v2.8.4: URL-encoded command substitution %24%28...%29 must be caught too
begin_test "path-guard: blocks URL-encoded command substitution (v2.8.4)"
PROJ=$(mktemp -d)
INPUT=$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s/foo%%24%%28id%%29.py","content":"x"},"cwd":"%s"}' "$PROJ" "$PROJ")
echo "$INPUT" | bash "$HOOK" >/dev/null 2>&1
[ "$?" -eq 2 ] && pass || fail "encoded command substitution not blocked"
rm -rf "$PROJ"

begin_test "path-guard: allows a normal relative config-like file (no false positive, v2.8.4)"
PROJ=$(mktemp -d)
INPUT=$(printf '{"tool_name":"Write","tool_input":{"file_path":"config/app.json","content":"{}"},"cwd":"%s"}' "$PROJ")
echo "$INPUT" | bash "$HOOK" >/dev/null 2>&1
[ "$?" -eq 0 ] && pass || fail "false positive on normal config/app.json"
rm -rf "$PROJ"

# v2.8.11: Claude Code's own file-memory store must be writable (was blocked by
# abs-path, silently breaking /remember + auto-memory under Supercharger).
# Resolved in BASH, the way the hook resolves it. python's expanduser returns
# %USERPROFILE% on Windows and ignores the HOME this suite sandboxes, so the test
# built a path under the real user's home while the guard was protecting the
# sandbox — two different homes, no match, and both assertions below reported the
# guard as failing to block. `cd && pwd -P` resolves symlinks without a fork into
# an interpreter that disagrees about what home means.
HOME_R=$(cd "$HOME" 2>/dev/null && pwd -P)
begin_test "path-guard: allows write to ~/.claude/projects/*/memory/*.md (v2.8.11)"
PROJ=$(mktemp -d)
INPUT=$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s/.claude/projects/-enc/memory/note.md","content":"x"},"cwd":"%s"}' "$HOME_R" "$PROJ")
echo "$INPUT" | bash "$HOOK" >/dev/null 2>&1
[ "$?" -eq 0 ] && pass || fail "memory-store .md write wrongly blocked"
rm -rf "$PROJ"

begin_test "path-guard: still blocks a non-.md file in the memory dir (v2.8.11)"
PROJ=$(mktemp -d)
INPUT=$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s/.claude/projects/-enc/memory/evil.sh","content":"x"},"cwd":"%s"}' "$HOME_R" "$PROJ")
echo "$INPUT" | bash "$HOOK" >/dev/null 2>&1
[ "$?" -eq 2 ] && pass || fail "non-.md write in memory dir should still be blocked"
rm -rf "$PROJ"

begin_test "path-guard: memory allowance does not weaken ~/.ssh protection (v2.8.11)"
PROJ=$(mktemp -d)
INPUT=$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s/.ssh/authorized_keys","content":"x"},"cwd":"%s"}' "$HOME_R" "$PROJ")
echo "$INPUT" | bash "$HOOK" >/dev/null 2>&1
[ "$?" -eq 2 ] && pass || fail "~/.ssh write must still be blocked"
rm -rf "$PROJ"

# v2.9.3: NotebookEdit (notebook_path) + MultiEdit are now covered — a notebook/
# multi-edit write outside the project (or to a protected path) must be blocked.
begin_test "path-guard: blocks NotebookEdit (notebook_path) outside project"
PROJ=$(mktemp -d)
INPUT=$(printf '{"tool_name":"NotebookEdit","tool_input":{"notebook_path":"/etc/evil.ipynb","new_source":"x"},"cwd":"%s"}' "$PROJ")
echo "$INPUT" | bash "$HOOK" >/dev/null 2>&1
[ "$?" -eq 2 ] && pass || fail "NotebookEdit outside project must be blocked"
rm -rf "$PROJ"

begin_test "path-guard: blocks MultiEdit (file_path) outside project"
PROJ=$(mktemp -d)
INPUT=$(printf '{"tool_name":"MultiEdit","tool_input":{"file_path":"/etc/evil.txt"},"cwd":"%s"}' "$PROJ")
echo "$INPUT" | bash "$HOOK" >/dev/null 2>&1
[ "$?" -eq 2 ] && pass || fail "MultiEdit outside project must be blocked"
rm -rf "$PROJ"

begin_test "path-guard: allows NotebookEdit inside the project"
PROJ=$(mktemp -d)
INPUT=$(printf '{"tool_name":"NotebookEdit","tool_input":{"notebook_path":"%s/analysis.ipynb","new_source":"x"},"cwd":"%s"}' "$PROJ" "$PROJ")
echo "$INPUT" | bash "$HOOK" >/dev/null 2>&1
[ "$?" -eq 0 ] && pass || fail "in-project NotebookEdit must be allowed"
rm -rf "$PROJ"

# v2.23.13: subdirectory-launch false positive. When Claude is launched from a
# subdir of the repo, a file at the REPO ROOT sits above cwd and was wrongly
# blocked as "outside project root". The boundary now widens to the enclosing
# git repo root (lazily), so in-repo writes at any level are allowed — while
# truly-outside paths and sibling repos still block.
REPO=$(mktemp -d)/repo; mkdir -p "$REPO/app"; ( cd "$REPO" && git init -q )
: > "$REPO/vercel.json"

begin_test "path-guard: allows repo-root file when cwd is a subdirectory (git repo)"
INPUT=$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s/vercel.json"},"cwd":"%s/app"}' "$REPO" "$REPO")
echo "$INPUT" | bash "$HOOK" >/dev/null 2>&1
[ "$?" -eq 0 ] && pass || fail "repo-root file from subdir cwd must be allowed"

begin_test "path-guard: still allows a file inside the subdir cwd"
INPUT=$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s/app/page.tsx"},"cwd":"%s/app"}' "$REPO" "$REPO")
echo "$INPUT" | bash "$HOOK" >/dev/null 2>&1
[ "$?" -eq 0 ] && pass || fail "in-subdir file must be allowed"

begin_test "path-guard: still blocks ~/.ssh from a subdir cwd (widening is repo-bounded)"
INPUT=$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s/.ssh/config"},"cwd":"%s/app"}' "$HOME" "$REPO")
echo "$INPUT" | bash "$HOOK" >/dev/null 2>&1
[ "$?" -eq 2 ] && pass || fail "~/.ssh must still be blocked"

begin_test "path-guard: non-git subdir keeps cwd boundary (parent file blocked)"
NG=$(mktemp -d); mkdir -p "$NG/sub"; : > "$NG/root.txt"   # NOT a git repo
INPUT=$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s/root.txt"},"cwd":"%s/sub"}' "$NG" "$NG")
echo "$INPUT" | bash "$HOOK" >/dev/null 2>&1
[ "$?" -eq 2 ] && pass || fail "no-git: parent file above cwd must stay blocked"
rm -rf "$NG"

rm -rf "$REPO"

report
