#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

HOOK="$REPO_DIR/hooks/tool-preferences.sh"

echo "=== tool-preferences Tests ==="

export SUPERCHARGER_NO_DEDUP=1

begin_test "tool-preferences: hook exists and is executable"
[ -x "$HOOK" ] && pass || fail "hook missing or not executable"

begin_test "tool-preferences: no .supercharger.json → silent allow"
PROJ=$(mktemp -d)
INPUT=$(printf '{"tool_name":"Bash","tool_input":{"command":"npm install"},"cwd":"%s"}' "$PROJ")
OUT=$(echo "$INPUT" | bash "$HOOK" 2>/dev/null)
[ -z "$OUT" ] && pass || fail "expected silent allow without config, got: $OUT"
rm -rf "$PROJ"

begin_test "tool-preferences: blocks npm with pnpm suggestion"
PROJ=$(mktemp -d)
echo '{"toolPreferences":{"npm":"pnpm"}}' > "$PROJ/.supercharger.json"
INPUT=$(printf '{"tool_name":"Bash","tool_input":{"command":"npm install react"},"cwd":"%s"}' "$PROJ")
OUT=$(echo "$INPUT" | bash "$HOOK" 2>/dev/null)
echo "$OUT" | grep -q 'permissionDecision.*deny' && echo "$OUT" | grep -q 'pnpm' && pass || fail "expected deny + pnpm suggestion, got: $OUT"
rm -rf "$PROJ"

begin_test "tool-preferences: allows preferred tool (pnpm)"
PROJ=$(mktemp -d)
echo '{"toolPreferences":{"npm":"pnpm"}}' > "$PROJ/.supercharger.json"
INPUT=$(printf '{"tool_name":"Bash","tool_input":{"command":"pnpm install react"},"cwd":"%s"}' "$PROJ")
OUT=$(echo "$INPUT" | bash "$HOOK" 2>/dev/null)
[ -z "$OUT" ] && pass || fail "expected silent allow for pnpm, got: $OUT"
rm -rf "$PROJ"

begin_test "tool-preferences: handles env var prefix (FOO=bar npm install)"
PROJ=$(mktemp -d)
echo '{"toolPreferences":{"npm":"pnpm"}}' > "$PROJ/.supercharger.json"
INPUT=$(printf '{"tool_name":"Bash","tool_input":{"command":"NODE_ENV=production npm install"},"cwd":"%s"}' "$PROJ")
OUT=$(echo "$INPUT" | bash "$HOOK" 2>/dev/null)
echo "$OUT" | grep -q 'permissionDecision.*deny' && pass || fail "expected deny with env prefix, got: $OUT"
rm -rf "$PROJ"

begin_test "tool-preferences: catches npx wrapper (npx jest → suggest vitest)"
PROJ=$(mktemp -d)
echo '{"toolPreferences":{"jest":"vitest"}}' > "$PROJ/.supercharger.json"
INPUT=$(printf '{"tool_name":"Bash","tool_input":{"command":"npx jest --watch"},"cwd":"%s"}' "$PROJ")
OUT=$(echo "$INPUT" | bash "$HOOK" 2>/dev/null)
echo "$OUT" | grep -q 'vitest' && pass || fail "expected vitest suggestion via npx, got: $OUT"
rm -rf "$PROJ"

begin_test "tool-preferences: SUPERCHARGER_TOOL_PREFS=0 disables hook"
PROJ=$(mktemp -d)
echo '{"toolPreferences":{"npm":"pnpm"}}' > "$PROJ/.supercharger.json"
INPUT=$(printf '{"tool_name":"Bash","tool_input":{"command":"npm install"},"cwd":"%s"}' "$PROJ")
OUT=$(SUPERCHARGER_TOOL_PREFS=0 bash -c "echo '$INPUT' | bash $HOOK" 2>/dev/null)
[ -z "$OUT" ] && pass || fail "expected disabled output, got: $OUT"
rm -rf "$PROJ"

begin_test "tool-preferences: skips non-Bash tools"
PROJ=$(mktemp -d)
echo '{"toolPreferences":{"npm":"pnpm"}}' > "$PROJ/.supercharger.json"
INPUT=$(printf '{"tool_name":"Edit","tool_input":{"file_path":"%s/foo.ts"},"cwd":"%s"}' "$PROJ" "$PROJ")
OUT=$(echo "$INPUT" | bash "$HOOK" 2>/dev/null)
[ -z "$OUT" ] && pass || fail "expected silent on Edit, got: $OUT"
rm -rf "$PROJ"

report
