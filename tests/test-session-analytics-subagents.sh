#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

TOOL="$REPO_DIR/tools/session-analytics.sh"

echo "=== Session Analytics --subagents Tests ==="

# ── Test 1: shows agent breakdown ──────────────────────────────────────
begin_test "subagent analytics: shows agent breakdown"
TMPDIR_SA=$(mktemp -d)
SCOPE_DIR="$TMPDIR_SA/.claude/supercharger/scope"
mkdir -p "$SCOPE_DIR"

cat > "$SCOPE_DIR/.subagent-costs-session1.jsonl" << 'EOF'
{"agent_id":"a1","agent_name":"code-helper","cost_usd":0.42,"tokens":28000,"duration_s":34}
{"agent_id":"a2","agent_name":"researcher","cost_usd":0.84,"tokens":60000,"duration_s":45}
{"agent_id":"a3","agent_name":"code-helper","cost_usd":0.21,"tokens":14000,"duration_s":22}
EOF

OUTPUT=$(HOME="$TMPDIR_SA" bash "$TOOL" --subagents --projects /nonexistent 2>&1 || true)
if echo "$OUTPUT" | grep -q "code-helper" && echo "$OUTPUT" | grep -q "researcher"; then
  pass
else
  fail "expected both agent names in output; got: $OUTPUT"
fi
rm -rf "$TMPDIR_SA"

# ── Test 2: no data shows message ──────────────────────────────────────
begin_test "subagent analytics: no data shows message"
TMPDIR_SA=$(mktemp -d)
SCOPE_DIR="$TMPDIR_SA/.claude/supercharger/scope"
mkdir -p "$SCOPE_DIR"

OUTPUT=$(HOME="$TMPDIR_SA" bash "$TOOL" --subagents --projects /nonexistent 2>&1 || true)
if echo "$OUTPUT" | grep -qi "No subagent data"; then
  pass
else
  fail "expected 'No subagent data' message; got: $OUTPUT"
fi
rm -rf "$TMPDIR_SA"

# ── Test 3: aggregates across sessions ─────────────────────────────────
begin_test "subagent analytics: aggregates across sessions"
TMPDIR_SA=$(mktemp -d)
SCOPE_DIR="$TMPDIR_SA/.claude/supercharger/scope"
mkdir -p "$SCOPE_DIR"

cat > "$SCOPE_DIR/.subagent-costs-session1.jsonl" << 'EOF'
{"agent_id":"a1","agent_name":"code-helper","cost_usd":1.00,"tokens":100000,"duration_s":30}
EOF

cat > "$SCOPE_DIR/.subagent-costs-session2.jsonl" << 'EOF'
{"agent_id":"a2","agent_name":"code-helper","cost_usd":0.50,"tokens":50000,"duration_s":20}
EOF

OUTPUT=$(HOME="$TMPDIR_SA" bash "$TOOL" --subagents --projects /nonexistent 2>&1 || true)
# Combined cost should be $1.50; combined tokens 150K => 150K; combined calls 2
if echo "$OUTPUT" | grep -q "code-helper" && echo "$OUTPUT" | grep -qE "1\.50|150K"; then
  pass
else
  fail "expected aggregated totals (cost 1.50 or 150K tokens); got: $OUTPUT"
fi
rm -rf "$TMPDIR_SA"

report
