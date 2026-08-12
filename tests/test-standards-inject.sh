#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

HOOK="$REPO_DIR/hooks/standards-inject.sh"

echo "=== standards-inject Hook Tests ==="

export SUPERCHARGER_NO_DEDUP=1
export SUPERCHARGER_TIER=standard

begin_test "standards-inject: hook file exists and is executable"
[ -x "$HOOK" ] && pass || fail "hook missing or not executable"

begin_test "standards-inject: detects vue project"
setup_test_home
PROJ=$(mktemp -d)
echo '{"dependencies":{"vue":"3.4.0"}}' > "$PROJ/package.json"
OUT=$(SUPERCHARGER_TIER=lean printf '{"cwd":"%s"}' "$PROJ" | SUPERCHARGER_TIER=lean bash "$HOOK" 2>/dev/null)
echo "$OUT" | grep -qi 'vue' && pass || fail "vue not matched: $OUT"
rm -rf "$PROJ"
teardown_test_home

begin_test "standards-inject: detects svelte project"
setup_test_home
PROJ=$(mktemp -d)
echo '{"dependencies":{"svelte":"4.0.0"}}' > "$PROJ/package.json"
OUT=$(SUPERCHARGER_TIER=lean printf '{"cwd":"%s"}' "$PROJ" | SUPERCHARGER_TIER=lean bash "$HOOK" 2>/dev/null)
echo "$OUT" | grep -qi 'svelte' && pass || fail "svelte not matched: $OUT"
rm -rf "$PROJ"
teardown_test_home

begin_test "standards-inject: detects rust project"
setup_test_home
PROJ=$(mktemp -d)
cat > "$PROJ/Cargo.toml" <<'EOF'
[package]
name = "x"
version = "0.1.0"
EOF
OUT=$(SUPERCHARGER_TIER=lean printf '{"cwd":"%s"}' "$PROJ" | SUPERCHARGER_TIER=lean bash "$HOOK" 2>/dev/null)
echo "$OUT" | grep -qi 'rust' && pass || fail "rust not matched: $OUT"
rm -rf "$PROJ"
teardown_test_home

begin_test "standards-inject: detects php project"
setup_test_home
PROJ=$(mktemp -d)
echo '{}' > "$PROJ/composer.json"
OUT=$(SUPERCHARGER_TIER=lean printf '{"cwd":"%s"}' "$PROJ" | SUPERCHARGER_TIER=lean bash "$HOOK" 2>/dev/null)
echo "$OUT" | grep -qi 'php' && pass || fail "php not matched: $OUT"
rm -rf "$PROJ"
teardown_test_home

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

# --- the digest tool this hook needs is absent on Git Bash --------------------
# Measured on the runner: the hook exited 127 having printed nothing, on every
# Windows session, SessionStart included. The TTL cache hashed the project path
# with `shasum`, which Git Bash does not ship — and under `set -euo pipefail` a
# missing command in that pipeline takes the whole hook down. The `2>/dev/null`
# suppressed the message, never the exit status, so it failed in total silence.
#
# Same class as v2.26.50, where md5sum AND md5 both turned out to be missing
# there; lib-hash.sh's sc_md5 exists for it and ends in a python3 tier.
#
# Every assertion above passes with the bug present, because macOS has shasum.
# Only removing the tool reproduces the platform, which is why this is a
# PATH-sandbox test rather than another content assertion.
begin_test "still emits when no shasum/md5sum exists (the Git Bash shape)"
setup_test_home
SB=$(mktemp -d)/bin
shim_tools "$SB" bash sh printf cat sed grep awk python3 date mkdir tr head tail \
  wc cut sort uniq stat rm touch mv cp chmod ls env jq dirname basename openssl
rm -f "$SB/shasum" "$SB/md5sum" "$SB/md5"
PROJ=$(mktemp -d)
echo '{"dependencies":{"vue":"3.4.0"}}' > "$PROJ/package.json"
OUT=$(printf '{"cwd":"%s"}' "$PROJ" \
  | env PATH="$SB" SUPERCHARGER_TIER=lean SUPERCHARGER_NO_DEDUP=1 bash "$HOOK" 2>&1)
RC=$?
rm -rf "$PROJ" "$(dirname "$SB")"
teardown_test_home
if [ "$RC" = "0" ] && printf '%s' "$OUT" | grep -qi 'vue'; then
  pass
else
  fail "hook died without a digest tool: rc=$RC out=$(printf '%s' "$OUT" | head -c 120)"
fi

report
