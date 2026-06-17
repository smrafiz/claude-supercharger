#!/usr/bin/env bash
# End-to-end tests for the v2.6.36 worktree-aware project root resolver:
# verify that hooks reading .supercharger.json find it in the MAIN repo even
# when their cwd points at a linked worktree.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

echo "=== Worktree-aware hooks (end-to-end) ==="

if ! command -v git >/dev/null 2>&1; then
  echo "skipping (git not available)"
  exit 0
fi

# Build the main repo + linked worktree fixture. Writes the supplied
# .supercharger.json into MAIN, then returns paths via MAIN/WT globals.
_mk_worktree_fixture() {
  local config_json="$1"
  TMP=$(mktemp -d)
  MAIN="$TMP/main"
  WT="$TMP/feat"
  git init -q "$MAIN"
  printf '%s\n' "$config_json" > "$MAIN/.supercharger.json"
  (cd "$MAIN" && git add . && git -c user.email=t@t -c user.name=t commit -q -m i)
  (cd "$MAIN" && git worktree add -q "$WT" -b feat >/dev/null 2>&1)
}
_rm_worktree_fixture() { rm -rf "$TMP"; }

# ── 1. cost-forecast: forecastTurnsPerAgent from main repo ────────────────────
begin_test "cost-forecast reads forecastTurnsPerAgent from main repo (worktree)"
setup_test_home
_mk_worktree_fixture '{"forecastTurnsPerAgent":50}'
SCOPE_DIR="$HOME/.claude/supercharger/scope"
mkdir -p "$SCOPE_DIR"
# avg $0.05/turn × 50 turns = $2.50 — well above the $0.10 threshold
printf '{"total_usd":0.50,"turn_count":10,"avg_per_turn":0.05}' > "$SCOPE_DIR/.session-cost"

PAYLOAD="{\"tool_name\":\"Agent\",\"cwd\":\"$WT\"}"
OUTPUT=$(printf '%s' "$PAYLOAD" | bash "$REPO_DIR/hooks/cost-forecast.sh" 2>&1)
# The 50 turns from MAIN must be reflected; the default would be 10 turns
if echo "$OUTPUT" | grep -q '~50 turns'; then
  pass
else
  fail "expected '~50 turns' in output (got: $OUTPUT)"
fi
_rm_worktree_fixture
teardown_test_home

# ── 2. budget-cap: budget threshold from main repo ────────────────────────────
begin_test "budget-cap reads budget from main repo (worktree)"
setup_test_home
_mk_worktree_fixture '{"budget":0.10}'
SCOPE_DIR="$HOME/.claude/supercharger/scope"
mkdir -p "$SCOPE_DIR"
# spent $0.15 > cap $0.10 → 100% over → block on non-readonly
printf '{"total_usd":0.15,"turn_count":5}' > "$SCOPE_DIR/.session-cost"

PAYLOAD="{\"tool_name\":\"Bash\",\"cwd\":\"$WT\"}"
OUTPUT=$(printf '%s' "$PAYLOAD" | bash "$REPO_DIR/hooks/budget-cap.sh" check 2>&1)
EXIT=$?
# Hook should block (exit 2) or at least emit a deny message
if [ "$EXIT" -eq 2 ] || echo "$OUTPUT" | grep -qi 'budget cap reached\|deny'; then
  pass
else
  fail "expected budget block (exit=$EXIT, output=$OUTPUT)"
fi
_rm_worktree_fixture
teardown_test_home

# ── 3. adaptive-economy: autoEconomy:false opt-out from main repo ─────────────
begin_test "adaptive-economy honors autoEconomy:false from main repo (worktree)"
setup_test_home
_mk_worktree_fixture '{"autoEconomy":false}'
SCOPE_DIR="$HOME/.claude/supercharger/scope"
mkdir -p "$SCOPE_DIR"
printf 'lean' > "$SCOPE_DIR/.economy-tier"

# 80% context with lean tier WOULD normally switch to minimal. Opt-out must suppress.
PAYLOAD="{\"cwd\":\"$WT\",\"context_window\":{\"used_percentage\":80}}"
OUTPUT=$(printf '%s' "$PAYLOAD" | bash "$REPO_DIR/hooks/adaptive-economy.sh" 2>&1)
if ! echo "$OUTPUT" | grep -q 'Auto-switched'; then
  pass
else
  fail "expected NO auto-switch (opt-out from main), got: $OUTPUT"
fi
_rm_worktree_fixture
teardown_test_home

# ── 4. tool-preferences: toolPreferences from main repo ───────────────────────
begin_test "tool-preferences reads toolPreferences from main repo (worktree)"
setup_test_home
_mk_worktree_fixture '{"toolPreferences":{"npm":"pnpm"}}'

PAYLOAD="{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"npm install\"},\"cwd\":\"$WT\"}"
OUTPUT=$(printf '%s' "$PAYLOAD" | bash "$REPO_DIR/hooks/tool-preferences.sh" 2>&1)
EXIT=$?
if [ "$EXIT" -eq 2 ] || echo "$OUTPUT" | grep -q 'pnpm'; then
  pass
else
  fail "expected pnpm preference message (exit=$EXIT, output=$OUTPUT)"
fi
_rm_worktree_fixture
teardown_test_home

# ── 5. path-guard: disableSecurityCategories from main repo ───────────────────
begin_test "path-guard honors disableSecurityCategories from main repo (worktree)"
setup_test_home
_mk_worktree_fixture '{"disableSecurityCategories":["path-traversal"]}'

# A path-traversal payload that would normally be blocked
PAYLOAD="{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"../../etc/passwd\"},\"cwd\":\"$WT\"}"
OUTPUT=$(printf '%s' "$PAYLOAD" | bash "$REPO_DIR/hooks/path-guard.sh" 2>&1)
EXIT=$?
# Category disabled → exit 0, no block. Without the worktree fix, the
# disable wouldn't be read from main and the hook would block.
if [ "$EXIT" -eq 0 ] && ! echo "$OUTPUT" | grep -qi 'path traversal'; then
  pass
else
  fail "expected category disable to suppress block (exit=$EXIT, output=$OUTPUT)"
fi
_rm_worktree_fixture
teardown_test_home

# ── 6. human-approval-gate: humanApprovalGate:true from main repo ─────────────
begin_test "human-approval-gate fires when enabled in main repo (worktree)"
setup_test_home
_mk_worktree_fixture '{"humanApprovalGate":true}'
SCOPE_DIR="$HOME/.claude/supercharger/scope"
mkdir -p "$SCOPE_DIR"

# Destructive Bash that the gate would catch (SQL drop pattern)
PAYLOAD="{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"psql -c 'DROP TABLE users'\"},\"cwd\":\"$WT\"}"
OUTPUT=$(printf '%s' "$PAYLOAD" | bash "$REPO_DIR/hooks/human-approval-gate.sh" 2>&1)
EXIT=$?
# First encounter → gate denies + writes pending file
if [ "$EXIT" -eq 2 ] || echo "$OUTPUT" | grep -qi 'sql\|approval\|deny'; then
  pass
else
  fail "expected gate to fire on DROP TABLE (exit=$EXIT, output=$OUTPUT)"
fi
_rm_worktree_fixture
teardown_test_home

echo "================================"
echo "Total: $TESTS_PASSED passed, $TESTS_FAILED failed"
