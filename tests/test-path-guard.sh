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
[ "$?" -eq 2 ] && pass || fail "relative symlink escape not blocked"
# legit relative write inside the project still allowed
INPUT=$(printf '{"tool_name":"Write","tool_input":{"file_path":"src/app.js","content":"x"},"cwd":"%s"}' "$PROJ")
echo "$INPUT" | bash "$HOOK" >/dev/null 2>&1
[ "$?" -eq 0 ] && pass || fail "legit in-project relative write wrongly blocked"
rm -rf "$PROJ"

report
