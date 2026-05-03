#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

HOOK="$REPO_DIR/hooks/confidence-gate.sh"

echo "=== confidence-gate Tests ==="

export SUPERCHARGER_NO_DEDUP=1
export SUPERCHARGER_TIER=standard

begin_test "confidence-gate: hook exists and is executable"
[ -x "$HOOK" ] && pass || fail "hook missing or not executable"

begin_test "confidence-gate: high score (no failures) emits no output"
setup_test_home
mkdir -p "$HOME/.claude/supercharger/scope"
echo '' > "$HOME/.claude/supercharger/scope/.tool-history"
INPUT='{"session_id":"sess1","tool_name":"Edit","tool_input":{"file_path":"/tmp/foo.txt"},"cwd":"/tmp"}'
OUT=$(echo "$INPUT" | bash "$HOOK" 2>/dev/null)
[ -z "$OUT" ] && pass || fail "expected silent allow, got: $OUT"
teardown_test_home

begin_test "confidence-gate: 3 recent failures triggers warn (systemMessage)"
setup_test_home
mkdir -p "$HOME/.claude/supercharger/scope"
HISTORY="$HOME/.claude/supercharger/scope/.tool-history"
cat > "$HISTORY" <<'EOF'
{"session_id": "sess1", "tool": "Bash", "success": false, "ts": 100}
{"session_id": "sess1", "tool": "Bash", "success": false, "ts": 101}
{"session_id": "sess1", "tool": "Bash", "success": false, "ts": 102}
{"session_id": "sess1", "tool": "Bash", "success": true, "ts": 103}
{"session_id": "sess1", "tool": "Bash", "success": true, "ts": 104}
EOF
printf '/tmp/foo.txt\t1\n' > "$HOME/.claude/supercharger/scope/.read-history"
INPUT='{"session_id":"sess1","tool_name":"Edit","tool_input":{"file_path":"/tmp/foo.txt"},"cwd":"/tmp"}'
OUT=$(echo "$INPUT" | bash "$HOOK" 2>/dev/null)
echo "$OUT" | grep -qi 'confidence' && pass || fail "expected confidence warn output, got: $OUT"
teardown_test_home

begin_test "confidence-gate: 5 recent failures triggers deny (permissionDecision)"
setup_test_home
mkdir -p "$HOME/.claude/supercharger/scope"
HISTORY="$HOME/.claude/supercharger/scope/.tool-history"
cat > "$HISTORY" <<'EOF'
{"session_id": "sess1", "tool": "Bash", "success": false, "ts": 100}
{"session_id": "sess1", "tool": "Bash", "success": false, "ts": 101}
{"session_id": "sess1", "tool": "Bash", "success": false, "ts": 102}
{"session_id": "sess1", "tool": "Bash", "success": false, "ts": 103}
{"session_id": "sess1", "tool": "Bash", "success": false, "ts": 104}
EOF
printf '/tmp/foo.txt\t1\n' > "$HOME/.claude/supercharger/scope/.read-history"
INPUT='{"session_id":"sess1","tool_name":"Edit","tool_input":{"file_path":"/tmp/foo.txt"},"cwd":"/tmp"}'
OUT=$(echo "$INPUT" | bash "$HOOK" 2>/dev/null)
echo "$OUT" | grep -q 'permissionDecision.*deny' && pass || fail "expected deny, got: $OUT"
teardown_test_home

report
