#!/usr/bin/env bash
# Claude Supercharger — Worktree end-to-end coverage for config-reading hooks
#
# Companion to test-worktree-resolver.sh (which unit-tests the resolver itself).
# Here we drive each wired hook in a real linked git worktree: .supercharger.json
# lives ONLY in the main repo, the hook runs with cwd = the linked worktree, and
# we assert it still honors the main-repo config. Each assertion is a
# discriminator — it fails if _resolve_project_root regresses to the raw cwd.
#
# Covers the 8 hooks that read .supercharger.json from a worktree-aware root:
# cost-forecast, budget-cap, human-approval-gate, project-config,
# adaptive-economy, path-guard, tool-preferences, post-compact-inject.

REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

HOOKS="$REPO_DIR/hooks"

echo "=== Worktree end-to-end hook coverage ==="

if ! command -v git >/dev/null 2>&1; then
  echo "skipping (git not available)"
  exit 0
fi

# Build a main repo + linked worktree, with $1 written as .supercharger.json in
# the MAIN repo only. Sets globals TMP / MAIN / WT.
mk_worktree() {
  TMP=$(mktemp -d)
  MAIN="$TMP/main"
  WT="$TMP/feat"
  git init -q "$MAIN"
  (cd "$MAIN" && touch a.txt && git add . && git -c user.email=t@t -c user.name=t commit -q -m i)
  (cd "$MAIN" && git worktree add -q "$WT" -b feat >/dev/null 2>&1)
  printf '%s\n' "$1" > "$MAIN/.supercharger.json"
}

scope_dir() { printf '%s/.claude/supercharger/scope' "$HOME"; }

# ── 1: cost-forecast reads forecastTurnsPerAgent from main repo ───────────────
begin_test "cost-forecast: forecastTurnsPerAgent from main repo (linked worktree)"
setup_test_home
mk_worktree '{"forecastTurnsPerAgent":50}'
mkdir -p "$(scope_dir)"
printf '{"avg_per_turn":0.10,"total_usd":1.0,"turn_count":10}\n' > "$(scope_dir)/.session-cost"
OUT=$(printf '{"tool_name":"Agent","cwd":"%s"}\n' "$WT" | bash "$HOOKS/cost-forecast.sh" 2>&1)
if printf '%s' "$OUT" | grep -q '50 turns'; then
  pass
else
  fail "expected '~50 turns' (default is 10), got: $OUT"
fi
teardown_test_home; rm -rf "$TMP"

# ── 2: budget-cap check reads budget cap from main repo ───────────────────────
begin_test "budget-cap: budget cap from main repo blocks over-budget tool (worktree)"
setup_test_home
mk_worktree '{"budget":0.01}'
mkdir -p "$(scope_dir)"
printf '{"total_usd":1.0,"turn_count":10}\n' > "$(scope_dir)/.session-cost"
OUT=$(printf '{"tool_name":"Bash","cwd":"%s"}\n' "$WT" | bash "$HOOKS/budget-cap.sh" check 2>&1)
EXIT=$?
if [ "$EXIT" -eq 2 ] || printf '%s' "$OUT" | grep -qi 'budget cap reached'; then
  pass
else
  fail "expected block on over-budget (exit=$EXIT): $OUT"
fi
teardown_test_home; rm -rf "$TMP"

# ── 3: human-approval-gate enabled via main repo config ───────────────────────
begin_test "human-approval-gate: humanApprovalGate from main repo gates risky cmd (worktree)"
setup_test_home
mk_worktree '{"humanApprovalGate":true}'
OUT=$(printf '{"tool_name":"Bash","cwd":"%s","tool_input":{"command":"git reset --hard HEAD~1"}}\n' "$WT" | bash "$HOOKS/human-approval-gate.sh" 2>&1)
EXIT=$?
if [ "$EXIT" -eq 2 ] || printf '%s' "$OUT" | grep -qi 'approval required'; then
  pass
else
  fail "expected gate to engage (exit=$EXIT): $OUT"
fi
teardown_test_home; rm -rf "$TMP"

# ── 4: project-config applies profile from main repo config ───────────────────
begin_test "project-config: profile from main repo written to scope (worktree)"
setup_test_home
mk_worktree '{"profile":"fast"}'
printf '{"cwd":"%s"}\n' "$WT" | bash "$HOOKS/project-config.sh" >/dev/null 2>&1
PROFILE_FILE="$(scope_dir)/.profile"
if [ -f "$PROFILE_FILE" ] && grep -q '^fast$' "$PROFILE_FILE"; then
  pass
else
  fail "expected scope/.profile=fast from main config; got: $(cat "$PROFILE_FILE" 2>/dev/null || echo MISSING)"
fi
teardown_test_home; rm -rf "$TMP"

# ── 5: adaptive-economy honors autoEconomy:false from main repo ───────────────
begin_test "adaptive-economy: autoEconomy:false from main repo suppresses switch (worktree)"
setup_test_home
mk_worktree '{"autoEconomy":false}'
mkdir -p "$(scope_dir)"
printf 'lean' > "$(scope_dir)/.economy-tier"
printf '{"cwd":"%s","context_window":{"used_percentage":85}}\n' "$WT" | bash "$HOOKS/adaptive-economy.sh" >/dev/null 2>&1
TIER=$(cat "$(scope_dir)/.economy-tier" 2>/dev/null)
if [ "$TIER" = "lean" ]; then
  pass
else
  fail "tier switched to '$TIER' — autoEconomy:false from main not honored"
fi
teardown_test_home; rm -rf "$TMP"

# ── 6: path-guard honors disableSecurityCategories from main repo ─────────────
begin_test "path-guard: disableSecurityCategories from main repo allows git-internals write (worktree)"
setup_test_home
mk_worktree '{"disableSecurityCategories":["git-internals"]}'
printf '{"tool_name":"Write","cwd":"%s","tool_input":{"file_path":".git/hooks/pre-commit"}}\n' "$WT" | bash "$HOOKS/path-guard.sh" >/dev/null 2>&1
EXIT=$?
if [ "$EXIT" -eq 0 ]; then
  pass
else
  fail "expected git-internals write allowed via main config (exit=$EXIT)"
fi
teardown_test_home; rm -rf "$TMP"

# ── 7: tool-preferences reads toolPreferences from main repo ──────────────────
begin_test "tool-preferences: toolPreferences from main repo suggests replacement (worktree)"
setup_test_home
mk_worktree '{"toolPreferences":{"npm":"pnpm"}}'
OUT=$(printf '{"tool_name":"Bash","cwd":"%s","tool_input":{"command":"npm install"}}\n' "$WT" | bash "$HOOKS/tool-preferences.sh" 2>&1)
EXIT=$?
if [ "$EXIT" -eq 2 ] || printf '%s' "$OUT" | grep -q 'pnpm'; then
  pass
else
  fail "expected pnpm suggestion from main config (exit=$EXIT): $OUT"
fi
teardown_test_home; rm -rf "$TMP"

# ── 8: post-compact-inject reads hints from main repo config ──────────────────
begin_test "post-compact-inject: hints from main repo injected after compaction (worktree)"
setup_test_home
mk_worktree '{"hints":"WORKTREE_TEST_HINT"}'
OUT=$(printf '{"cwd":"%s"}\n' "$WT" | bash "$HOOKS/post-compact-inject.sh" 2>&1)
if printf '%s' "$OUT" | grep -q 'WORKTREE_TEST_HINT'; then
  pass
else
  fail "expected main-repo hints in post-compact output: $OUT"
fi
teardown_test_home; rm -rf "$TMP"

echo "================================"
echo "Total: $TESTS_PASSED passed, $TESTS_FAILED failed"
