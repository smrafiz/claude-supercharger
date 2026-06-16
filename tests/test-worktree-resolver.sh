#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

LIB="$REPO_DIR/hooks/lib-project-root.sh"
HOOK_TLC="$REPO_DIR/hooks/tool-call-limiter.sh"

echo "=== Worktree-aware project root resolver ==="

# Tests run in a sandbox git world; skip if git unavailable.
if ! command -v git >/dev/null 2>&1; then
  echo "skipping (git not available)"
  exit 0
fi

# ── Test 1: resolver returns cwd in a non-git directory ───────────────────────
begin_test "resolves to cwd in non-git directory"
TMP=$(mktemp -d)
# shellcheck source=hooks/lib-project-root.sh
source "$LIB"
GOT=$(_resolve_project_root "$TMP")
if [ "$GOT" = "$TMP" ]; then
  pass
else
  fail "expected $TMP, got $GOT"
fi
rm -rf "$TMP"

# ── Test 2: resolver returns cwd in main worktree ─────────────────────────────
begin_test "resolves to cwd in main worktree"
TMP=$(mktemp -d)
git init -q "$TMP"
(cd "$TMP" && touch a.txt && git add . && git -c user.email=t@t -c user.name=t commit -q -m i)
source "$LIB"
GOT=$(_resolve_project_root "$TMP")
GOT_REAL=$(cd "$GOT" && pwd)
TMP_REAL=$(cd "$TMP" && pwd)
if [ "$GOT_REAL" = "$TMP_REAL" ]; then
  pass
else
  fail "expected $TMP_REAL, got $GOT_REAL"
fi
rm -rf "$TMP"

# ── Test 3: resolver returns MAIN repo root from a linked worktree ────────────
begin_test "resolves to main repo root from a linked worktree"
TMP=$(mktemp -d)
MAIN="$TMP/main"
WT="$TMP/feat"
git init -q "$MAIN"
(cd "$MAIN" && touch a.txt && git add . && git -c user.email=t@t -c user.name=t commit -q -m i)
(cd "$MAIN" && git worktree add -q "$WT" -b feat 2>&1 >/dev/null)
source "$LIB"
GOT=$(_resolve_project_root "$WT")
# The resolver follows symlinks (macOS /var → /private/var); canonicalize both sides.
MAIN_REAL=$(cd "$MAIN" && pwd -P)
GOT_REAL=$(cd "$GOT" 2>/dev/null && pwd -P)
if [ "$GOT_REAL" = "$MAIN_REAL" ]; then
  pass
else
  fail "expected $MAIN_REAL, got $GOT_REAL (from worktree $WT)"
fi
rm -rf "$TMP"

# ── Test 4: tool-call-limiter reads .supercharger.json from main repo when CWD
#            is a linked worktree (end-to-end smoke test).
begin_test "tool-call-limiter sees maxToolCalls from main repo (linked worktree)"
setup_test_home
TMP=$(mktemp -d)
MAIN="$TMP/main"
WT="$TMP/feat"
git init -q "$MAIN"
printf '{"maxToolCalls":5}\n' > "$MAIN/.supercharger.json"
(cd "$MAIN" && git add . && git -c user.email=t@t -c user.name=t commit -q -m i)
(cd "$MAIN" && git worktree add -q "$WT" -b feat 2>&1 >/dev/null)

# Simulate "current tool call count = 6" (above cap of 5). Hook should block.
SCOPE_DIR="$HOME/.claude/supercharger/scope"
mkdir -p "$SCOPE_DIR"
SESSION_KEY="test-$$"
printf '6' > "$SCOPE_DIR/.tool-calls-${SESSION_KEY}"

PAYLOAD="{\"tool_name\":\"Bash\",\"cwd\":\"$WT\"}"
OUTPUT=$(CLAUDE_SESSION_ID="$SESSION_KEY" echo "$PAYLOAD" | CLAUDE_SESSION_ID="$SESSION_KEY" bash "$HOOK_TLC" 2>&1)
EXIT=$?
# At 6/5, hook should warn or block. We just need it to ACT on the cap (not silently skip).
if [ "$EXIT" -ne 0 ] || echo "$OUTPUT" | grep -qi 'cap\|limit\|deny'; then
  pass
else
  fail "expected hook to act on cap (exit=$EXIT, output=$OUTPUT)"
fi
teardown_test_home
rm -rf "$TMP"

echo "================================"
echo "Total: $TESTS_PASSED passed, $TESTS_FAILED failed"
