#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

HOOK="$REPO_DIR/hooks/confidence-gate.sh"

echo "=== confidence-gate Tests ==="

export SUPERCHARGER_NO_DEDUP=1
export SUPERCHARGER_TIER=standard

begin_test "confidence-gate: hook exists and is executable"
[ -x "$HOOK" ] && pass || fail "hook missing or not executable"

# v2.14.2 perf fast-path: inert Bash is never gated → skips the score computation.
begin_test "confidence-gate(fast-path): inert Bash (ls) is allowed"
printf '{"tool_name":"Bash","tool_input":{"command":"ls -la"}}' | bash "$HOOK" >/dev/null 2>&1
[ "$?" -eq 0 ] && pass || fail "inert Bash was gated"

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
printf '/tmp/foo.txt\t1\n' > "$HOME/.claude/supercharger/scope/.read-history-sess1"
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
printf '/tmp/foo.txt\t1\n' > "$HOME/.claude/supercharger/scope/.read-history-sess1"
INPUT='{"session_id":"sess1","tool_name":"Edit","tool_input":{"file_path":"/tmp/foo.txt"},"cwd":"/tmp"}'
OUT=$(echo "$INPUT" | bash "$HOOK" 2>/dev/null)
echo "$OUT" | grep -q 'permissionDecision.*deny' && pass || fail "expected deny, got: $OUT"
teardown_test_home

begin_test "confidence-gate: Edit on unread file triggers read-before-write deduction"
setup_test_home
mkdir -p "$HOME/.claude/supercharger/scope"
echo '{"session_id": "sess1", "tool": "Bash", "success": false, "ts": 100}' > "$HOME/.claude/supercharger/scope/.tool-history"
echo '' > "$HOME/.claude/supercharger/scope/.read-history-sess1"
INPUT='{"session_id":"sess1","tool_name":"Edit","tool_input":{"file_path":"/tmp/never-read.txt"},"cwd":"/tmp"}'
OUT=$(echo "$INPUT" | bash "$HOOK" 2>/dev/null)
echo "$OUT" | grep -qi 'read-before-write' && pass || fail "expected read-before-write reason, got: $OUT"
teardown_test_home

begin_test "confidence-gate: Edit on previously-read file does NOT trigger violation"
setup_test_home
mkdir -p "$HOME/.claude/supercharger/scope"
echo '' > "$HOME/.claude/supercharger/scope/.tool-history"
printf '/tmp/known.txt\t12345\n' > "$HOME/.claude/supercharger/scope/.read-history-sess1"
INPUT='{"session_id":"sess1","tool_name":"Edit","tool_input":{"file_path":"/tmp/known.txt"},"cwd":"/tmp"}'
OUT=$(echo "$INPUT" | bash "$HOOK" 2>/dev/null)
[ -z "$OUT" ] && pass || fail "expected silent allow on known file, got: $OUT"
teardown_test_home

begin_test "confidence-gate: repetition flag + 1 failure triggers warn"
setup_test_home
mkdir -p "$HOME/.claude/supercharger/scope"
HISTORY="$HOME/.claude/supercharger/scope/.tool-history"
echo '{"session_id": "sess1", "tool": "Bash", "success": false, "ts": 100}' > "$HISTORY"
printf '/tmp/known.txt\t12345\n' > "$HOME/.claude/supercharger/scope/.read-history-sess1"
touch "$HOME/.claude/supercharger/scope/.repetition-flag-sess1"
INPUT='{"session_id":"sess1","tool_name":"Edit","tool_input":{"file_path":"/tmp/known.txt"},"cwd":"/tmp"}'
OUT=$(echo "$INPUT" | bash "$HOOK" 2>/dev/null)
echo "$OUT" | grep -qi 'repetition flagged' && pass || fail "expected repetition reason, got: $OUT"
teardown_test_home

begin_test "confidence-gate: non-destructive Bash bypasses gate"
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
INPUT='{"session_id":"sess1","tool_name":"Bash","tool_input":{"command":"ls -la"},"cwd":"/tmp"}'
OUT=$(echo "$INPUT" | bash "$HOOK" 2>/dev/null)
[ -z "$OUT" ] && pass || fail "expected silent allow for ls, got: $OUT"
teardown_test_home

begin_test "confidence-gate: destructive Bash gates with low score"
setup_test_home
mkdir -p "$HOME/.claude/supercharger/scope"
HISTORY="$HOME/.claude/supercharger/scope/.tool-history"
cat > "$HISTORY" <<'EOF'
{"session_id": "sess1", "tool": "Bash", "success": false, "ts": 100}
{"session_id": "sess1", "tool": "Bash", "success": false, "ts": 101}
{"session_id": "sess1", "tool": "Bash", "success": false, "ts": 102}
EOF
INPUT='{"session_id":"sess1","tool_name":"Bash","tool_input":{"command":"rm -rf /tmp/test"},"cwd":"/tmp"}'
OUT=$(echo "$INPUT" | bash "$HOOK" 2>/dev/null)
echo "$OUT" | grep -qi 'confidence' && pass || fail "expected gate output for rm, got: $OUT"
teardown_test_home

begin_test "confidence-gate: SUPERCHARGER_CONFIDENCE=0 disables gate"
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
INPUT='{"session_id":"sess1","tool_name":"Edit","tool_input":{"file_path":"/tmp/foo.txt"},"cwd":"/tmp"}'
OUT=$(SUPERCHARGER_CONFIDENCE=0 bash -c "echo '$INPUT' | bash $HOOK" 2>/dev/null)
[ -z "$OUT" ] && pass || fail "expected disabled output, got: $OUT"
teardown_test_home

begin_test "confidence-gate: minimal tier emits short tag"
setup_test_home
mkdir -p "$HOME/.claude/supercharger/scope"
HISTORY="$HOME/.claude/supercharger/scope/.tool-history"
cat > "$HISTORY" <<'EOF'
{"session_id": "sess1", "tool": "Bash", "success": false, "ts": 100}
{"session_id": "sess1", "tool": "Bash", "success": false, "ts": 101}
{"session_id": "sess1", "tool": "Bash", "success": false, "ts": 102}
EOF
printf '/tmp/known.txt\t1\n' > "$HOME/.claude/supercharger/scope/.read-history-sess1"
INPUT='{"session_id":"sess1","tool_name":"Edit","tool_input":{"file_path":"/tmp/known.txt"},"cwd":"/tmp"}'
OUT=$(SUPERCHARGER_TIER=minimal bash -c "echo '$INPUT' | bash $HOOK" 2>/dev/null)
echo "$OUT" | grep -q 'conf:' && pass || fail "minimal tag missing: $OUT"
teardown_test_home

# v2.8.14: read-before-write must consult the SESSION-scoped read history, not the
# deprecated GLOBAL .read-history — else another session's/project's stale reads
# mask a real blind edit. A file recorded only in the global file must NOT satisfy rbw.
begin_test "confidence-gate: ignores deprecated global .read-history (v2.8.14 scoping)"
setup_test_home
mkdir -p "$HOME/.claude/supercharger/scope"
printf '/tmp/gf.txt\t1\n' > "$HOME/.claude/supercharger/scope/.read-history"   # global only
cat > "$HOME/.claude/supercharger/scope/.tool-history-sessB" <<'EOF'
{"session_id": "sessB", "tool": "Bash", "success": false, "ts": 1}
{"session_id": "sessB", "tool": "Bash", "success": false, "ts": 2}
EOF
INPUT='{"session_id":"sessB","tool_name":"Edit","tool_input":{"file_path":"/tmp/gf.txt"},"cwd":"/tmp"}'
OUT=$(SUPERCHARGER_TIER=minimal bash -c "echo '$INPUT' | bash $HOOK" 2>/dev/null)
# global read ignored -> rbw=1 -> score = 1 - 0.40(2 fails) - 0.30(rbw) = 0.30
echo "$OUT" | grep -qE 'conf:0\.30' && pass || fail "global .read-history must be ignored (expected conf:0.30 with rbw; a leak would show 0.60): $OUT"
teardown_test_home

report
