#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

HOOK="$REPO_DIR/hooks/auto-compact.sh"

echo "=== Auto Compact Hook Tests ==="

SCOPE_DIR=""

setup_scope() {
  SCOPE_DIR=$(mktemp -d)
  export HOME="$SCOPE_DIR"
  mkdir -p "$SCOPE_DIR/.claude/supercharger/scope"
}

teardown_scope() {
  [ -n "$SCOPE_DIR" ] && rm -rf "$SCOPE_DIR"
}

input_pct() {
  printf '{"tool_name":"Bash","tool_input":{"command":"ls"},"context_window":{"used_percentage":%s}}' "$1"
}

# ── graceful exits ─────────────────────────────────────────────────────────────
begin_test "auto-compact: exits 0 silently when no context_window in input"
setup_scope
EXIT=0
OUT=$(echo '{"tool_name":"Bash","tool_input":{"command":"ls"}}' | HOME="$SCOPE_DIR" bash "$HOOK" 2>/dev/null) || EXIT=$?
[ "$EXIT" -eq 0 ] && [ -z "$OUT" ] && pass || fail "expected silent exit 0; exit=$EXIT out='$OUT'"
teardown_scope

begin_test "auto-compact: exits 0 silently below 70%"
setup_scope
EXIT=0
OUT=$(input_pct 65 | HOME="$SCOPE_DIR" bash "$HOOK" 2>/dev/null) || EXIT=$?
[ "$EXIT" -eq 0 ] && [ -z "$OUT" ] && pass || fail "expected silent exit 0 at 65%; exit=$EXIT"
teardown_scope

# ── threshold messages ────────────────────────────────────────────────────────
begin_test "auto-compact: produces message at 70%"
setup_scope
OUT=$(input_pct 70 | HOME="$SCOPE_DIR" bash "$HOOK" 2>/dev/null)
echo "$OUT" | grep -q "systemMessage" && pass || fail "expected systemMessage at 70%; got: $OUT"
teardown_scope

begin_test "auto-compact: 70% message contains CTX"
setup_scope
OUT=$(input_pct 72 | HOME="$SCOPE_DIR" bash "$HOOK" 2>/dev/null)
echo "$OUT" | grep -q "CTX" && pass || fail "expected CTX in message; got: $OUT"
teardown_scope

begin_test "auto-compact: 80% message contains HIGH or compact"
setup_scope
OUT=$(input_pct 82 | HOME="$SCOPE_DIR" bash "$HOOK" 2>/dev/null)
echo "$OUT" | grep -qi "HIGH\|compact" && pass || fail "expected HIGH/compact in 80% message; got: $OUT"
teardown_scope

begin_test "auto-compact: 90% message contains CRITICAL"
setup_scope
OUT=$(input_pct 91 | HOME="$SCOPE_DIR" bash "$HOOK" 2>/dev/null)
echo "$OUT" | grep -qi "CRITICAL" && pass || fail "expected CRITICAL in 90% message; got: $OUT"
teardown_scope

# ── debounce ──────────────────────────────────────────────────────────────────
begin_test "auto-compact: debounce — same band fires only once"
setup_scope
input_pct 75 | HOME="$SCOPE_DIR" bash "$HOOK" >/dev/null 2>&1
OUT=$(input_pct 77 | HOME="$SCOPE_DIR" bash "$HOOK" 2>/dev/null)
[ -z "$OUT" ] && pass || fail "expected no output on second 70-band call; got: $OUT"
teardown_scope

begin_test "auto-compact: debounce — higher band fires after lower band"
setup_scope
input_pct 75 | HOME="$SCOPE_DIR" bash "$HOOK" >/dev/null 2>&1
OUT=$(input_pct 85 | HOME="$SCOPE_DIR" bash "$HOOK" 2>/dev/null)
echo "$OUT" | grep -q "systemMessage" && pass || fail "expected message when crossing to 80-band; got: $OUT"
teardown_scope

begin_test "auto-compact: debounce — state cleared when context drops below 70%"
setup_scope
input_pct 75 | HOME="$SCOPE_DIR" bash "$HOOK" >/dev/null 2>&1
input_pct 60 | HOME="$SCOPE_DIR" bash "$HOOK" >/dev/null 2>&1
OUT=$(input_pct 71 | HOME="$SCOPE_DIR" bash "$HOOK" 2>/dev/null)
echo "$OUT" | grep -q "systemMessage" && pass || fail "expected message after reset; got: $OUT"
teardown_scope

begin_test "auto-compact: debounce — state file written on first trigger"
setup_scope
input_pct 75 | HOME="$SCOPE_DIR" bash "$HOOK" >/dev/null 2>&1
[ -f "$SCOPE_DIR/.claude/supercharger/scope/.compact-last-band" ] && pass || fail "state file not created"
teardown_scope

begin_test "auto-compact: debounce — state file cleared below 70%"
setup_scope
input_pct 75 | HOME="$SCOPE_DIR" bash "$HOOK" >/dev/null 2>&1
input_pct 60 | HOME="$SCOPE_DIR" bash "$HOOK" >/dev/null 2>&1
[ ! -f "$SCOPE_DIR/.claude/supercharger/scope/.compact-last-band" ] && pass || fail "state file should be cleared"
teardown_scope

# ── output format ─────────────────────────────────────────────────────────────
begin_test "auto-compact: output is valid JSON"
setup_scope
OUT=$(input_pct 75 | HOME="$SCOPE_DIR" bash "$HOOK" 2>/dev/null)
echo "$OUT" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null && pass || fail "output not valid JSON: $OUT"
teardown_scope

report
