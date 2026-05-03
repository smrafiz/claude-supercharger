#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

HOOK="$REPO_DIR/hooks/standards-inject.sh"

echo "=== standards-inject Hook Tests ==="

export SUPERCHARGER_NO_DEDUP=1
export SUPERCHARGER_TIER=standard

begin_test "standards-inject: hook file exists and is executable"
[ -x "$HOOK" ] && pass || fail "hook missing or not executable"

begin_test "standards-inject: minimal tier emits stack tag"
setup_test_home
PROJ=$(mktemp -d)
echo '{"dependencies":{"react":"18.0.0"}}' > "$PROJ/package.json"
OUT=$(SUPERCHARGER_TIER=minimal printf '{"cwd":"%s"}' "$PROJ" | SUPERCHARGER_TIER=minimal bash "$HOOK" 2>/dev/null)
echo "$OUT" | grep -qi 'react' && pass || fail "no react tag in minimal output: $OUT"
rm -rf "$PROJ"
teardown_test_home

begin_test "standards-inject: lean tier includes Forbidden section"
setup_test_home
PROJ=$(mktemp -d)
echo '{"dependencies":{"react":"18.0.0"}}' > "$PROJ/package.json"
OUT=$(SUPERCHARGER_TIER=lean printf '{"cwd":"%s"}' "$PROJ" | SUPERCHARGER_TIER=lean bash "$HOOK" 2>/dev/null)
echo "$OUT" | grep -qi 'forbidden' && pass || fail "Forbidden section missing in lean output"
rm -rf "$PROJ"
teardown_test_home

begin_test "standards-inject: lean tier includes Toolchain section"
setup_test_home
PROJ=$(mktemp -d)
echo '{"dependencies":{"react":"18.0.0"}}' > "$PROJ/package.json"
OUT=$(SUPERCHARGER_TIER=lean printf '{"cwd":"%s"}' "$PROJ" | SUPERCHARGER_TIER=lean bash "$HOOK" 2>/dev/null)
echo "$OUT" | grep -qi 'toolchain' && pass || fail "Toolchain section missing in lean output"
rm -rf "$PROJ"
teardown_test_home

begin_test "standards-inject: lean tier excludes Pitfalls section"
setup_test_home
PROJ=$(mktemp -d)
echo '{"dependencies":{"react":"18.0.0"}}' > "$PROJ/package.json"
OUT=$(SUPERCHARGER_TIER=lean printf '{"cwd":"%s"}' "$PROJ" | SUPERCHARGER_TIER=lean bash "$HOOK" 2>/dev/null)
echo "$OUT" | grep -qi 'pitfalls' && fail "Pitfalls leaked into lean output" || pass
rm -rf "$PROJ"
teardown_test_home

begin_test "standards-inject: standard tier includes Pitfalls section"
setup_test_home
PROJ=$(mktemp -d)
echo '{"dependencies":{"react":"18.0.0"}}' > "$PROJ/package.json"
OUT=$(SUPERCHARGER_TIER=standard printf '{"cwd":"%s"}' "$PROJ" | SUPERCHARGER_TIER=standard bash "$HOOK" 2>/dev/null)
echo "$OUT" | grep -qi 'pitfalls' && pass || fail "Pitfalls missing in standard output"
rm -rf "$PROJ"
teardown_test_home

begin_test "standards-inject: user override at ~/.claude/rules/stacks/ wins over bundled"
setup_test_home
mkdir -p "$HOME/.claude/rules/stacks"
cat > "$HOME/.claude/rules/stacks/react.md" <<'EOF'
---
stack: react
---

## Forbidden
- USER_OVERRIDE_MARKER

## Toolchain
- test: jest
EOF
PROJ=$(mktemp -d)
echo '{"dependencies":{"react":"18.0.0"}}' > "$PROJ/package.json"
OUT=$(SUPERCHARGER_TIER=lean printf '{"cwd":"%s"}' "$PROJ" | SUPERCHARGER_TIER=lean bash "$HOOK" 2>/dev/null)
echo "$OUT" | grep -q 'USER_OVERRIDE_MARKER' && pass || fail "user override not used: $OUT"
rm -rf "$PROJ"
teardown_test_home

begin_test "standards-inject: multi-stack project emits both, primary first"
setup_test_home
PROJ=$(mktemp -d)
echo '{"dependencies":{"next":"14.0.0","react":"18.0.0"}}' > "$PROJ/package.json"
OUT=$(SUPERCHARGER_TIER=lean printf '{"cwd":"%s"}' "$PROJ" | SUPERCHARGER_TIER=lean bash "$HOOK" 2>/dev/null)
NEXT_POS=$(echo "$OUT" | grep -n '# nextjs' | head -1 | cut -d: -f1)
REACT_POS=$(echo "$OUT" | grep -n '# react' | head -1 | cut -d: -f1)
[ -n "$NEXT_POS" ] && [ -n "$REACT_POS" ] && pass || fail "expected both nextjs and react sections in output"
rm -rf "$PROJ"
teardown_test_home

begin_test "standards-inject: SUPERCHARGER_STANDARDS=0 produces empty output"
setup_test_home
PROJ=$(mktemp -d)
echo '{"dependencies":{"react":"18.0.0"}}' > "$PROJ/package.json"
OUT=$(SUPERCHARGER_STANDARDS=0 printf '{"cwd":"%s"}' "$PROJ" | SUPERCHARGER_STANDARDS=0 bash "$HOOK" 2>/dev/null)
[ -z "$OUT" ] && pass || fail "expected empty output, got: $OUT"
rm -rf "$PROJ"
teardown_test_home

begin_test "standards-inject: empty directory produces no output"
setup_test_home
PROJ=$(mktemp -d)
OUT=$(printf '{"cwd":"%s"}' "$PROJ" | bash "$HOOK" 2>/dev/null)
[ -z "$OUT" ] && pass || fail "expected empty output for empty dir, got: $OUT"
rm -rf "$PROJ"
teardown_test_home

report
