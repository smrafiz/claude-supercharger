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

report
