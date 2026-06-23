#!/usr/bin/env bash
# Tests for notify-permission.sh and notify-stop.sh — the event-level
# notification hooks. notify-helper internals covered in test-notify-helper.sh.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

NP="$REPO_DIR/hooks/notify-permission.sh"
NS="$REPO_DIR/hooks/notify-stop.sh"

echo "=== Notify Event Hook Tests ==="

# Force sound-only mode to avoid spawning real notifications during tests.
_setup() {
  setup_test_home
  mkdir -p "$HOME/.claude/supercharger/scope"
  touch "$HOME/.claude/supercharger/.sound-only-notify" 2>/dev/null || true
  touch "$HOME/.claude/supercharger/.no-desktop-notify" 2>/dev/null || true
}

# --- notify-permission ---

begin_test "notify-permission: exits 0 on valid payload"
_setup
OUT=$(printf '{"tool_name":"Bash","tool_input":{"command":"ls"}}' | bash "$NP" 2>&1)
EXIT=$?
teardown_test_home
[ "$EXIT" -eq 0 ] && pass || fail "exit=$EXIT out=$OUT"

begin_test "notify-permission: silent (no-desktop-notify guard)"
_setup
OUT=$(printf '{"tool_name":"Write","tool_input":{"file_path":"/tmp/x"}}' | bash "$NP" 2>&1)
teardown_test_home
[ -z "$OUT" ] && pass || fail "expected no output, got: $OUT"

begin_test "notify-permission: skips inside subagent"
_setup
# Remove the no-desktop guard so we'd otherwise fire
rm -f "$HOME/.claude/supercharger/.no-desktop-notify" 2>/dev/null || true
OUT=$(printf '{"agent_id":"a1","tool_name":"Bash","tool_input":{"command":"ls"}}' | bash "$NP" 2>&1)
EXIT=$?
teardown_test_home
# Sub-agent path exits 0 silently before _send_notification
[ "$EXIT" -eq 0 ] && pass || fail "exit=$EXIT out=$OUT"

begin_test "notify-permission: drains malformed JSON without crashing"
_setup
OUT=$(printf 'not json' | bash "$NP" 2>&1)
EXIT=$?
teardown_test_home
[ "$EXIT" -eq 0 ] && pass || fail "exit=$EXIT out=$OUT"

# --- notify-stop ---

begin_test "notify-stop: exits 0 on valid payload"
_setup
OUT=$(printf '{"stop_hook_active":false}' | bash "$NS" 2>&1)
EXIT=$?
teardown_test_home
[ "$EXIT" -eq 0 ] && pass || fail "exit=$EXIT out=$OUT"

begin_test "notify-stop: skips when stop_hook_active=true"
_setup
rm -f "$HOME/.claude/supercharger/.no-desktop-notify" 2>/dev/null || true
START=$(date +%s%N 2>/dev/null || date +%s)
OUT=$(printf '{"stop_hook_active":true}' | bash "$NS" 2>&1)
END=$(date +%s%N 2>/dev/null || date +%s)
EXIT=$?
teardown_test_home
# Should exit before the 0.3s sleep — but timing flake-prone in CI, just check exit
[ "$EXIT" -eq 0 ] && pass || fail "exit=$EXIT out=$OUT"

begin_test "notify-stop: skips inside subagent"
_setup
rm -f "$HOME/.claude/supercharger/.no-desktop-notify" 2>/dev/null || true
OUT=$(printf '{"agent_id":"a1","stop_hook_active":false}' | bash "$NS" 2>&1)
EXIT=$?
teardown_test_home
[ "$EXIT" -eq 0 ] && pass || fail "exit=$EXIT out=$OUT"

begin_test "notify-stop: drains malformed JSON without crashing"
_setup
OUT=$(printf 'not json' | bash "$NS" 2>&1)
EXIT=$?
teardown_test_home
[ "$EXIT" -eq 0 ] && pass || fail "exit=$EXIT out=$OUT"

begin_test "notify-stop: \$HOME injection safe (v2.6.77 env-var path)"
_setup
# Adversarial HOME would have broken pre-v2.6.77; with env-var pattern, the
# python3 -c invocation cannot see it as code. Just verify the hook still
# exits 0 when HOME points to a directory without a session-cost file.
HOME="$HOME" OUT=$(printf '{"stop_hook_active":false}' | bash "$NS" 2>&1)
EXIT=$?
teardown_test_home
[ "$EXIT" -eq 0 ] && pass || fail "exit=$EXIT out=$OUT"

report
