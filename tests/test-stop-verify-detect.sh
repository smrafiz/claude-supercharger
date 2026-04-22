#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

STOP_VERIFY="$REPO_DIR/hooks/stop-verify.sh"

# Source only the detect_test_cmd function from the hook
eval "$(grep -A 30 '^detect_test_cmd()' "$STOP_VERIFY")"

echo "=== stop-verify detect_test_cmd Tests ==="

# ── npm test ──
begin_test "stop-verify: detects npm test"
TMP=$(mktemp -d)
printf '{"scripts":{"test":"jest"}}' > "$TMP/package.json"
RESULT=$(detect_test_cmd "$TMP")
rm -rf "$TMP"
if [ "$RESULT" = "npm test" ]; then pass; else fail "expected 'npm test', got '$RESULT'"; fi

# ── pnpm test ──
begin_test "stop-verify: detects pnpm test"
TMP=$(mktemp -d)
printf '{"scripts":{"test":"jest"}}' > "$TMP/package.json"
touch "$TMP/pnpm-lock.yaml"
RESULT=$(detect_test_cmd "$TMP")
rm -rf "$TMP"
if [ "$RESULT" = "pnpm test" ]; then pass; else fail "expected 'pnpm test', got '$RESULT'"; fi

# ── pytest ──
begin_test "stop-verify: detects pytest"
TMP=$(mktemp -d)
touch "$TMP/pyproject.toml"
RESULT=$(detect_test_cmd "$TMP")
rm -rf "$TMP"
if [ "$RESULT" = "pytest" ]; then pass; else fail "expected 'pytest', got '$RESULT'"; fi

# ── cargo test ──
begin_test "stop-verify: detects cargo test"
TMP=$(mktemp -d)
touch "$TMP/Cargo.toml"
RESULT=$(detect_test_cmd "$TMP")
rm -rf "$TMP"
if [ "$RESULT" = "cargo test" ]; then pass; else fail "expected 'cargo test', got '$RESULT'"; fi

report
