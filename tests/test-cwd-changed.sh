#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

HOOK="$REPO_DIR/hooks/cwd-changed.sh"

echo "=== CwdChanged Hook Tests ==="

export SUPERCHARGER_NO_DEDUP=1

begin_test "cwd-changed: emits systemMessage when stack detected in new dir"
setup_test_home
PROJ=$(mktemp -d)
echo '{"dependencies":{"react":"18.0.0"},"devDependencies":{"typescript":"5.0.0"}}' > "$PROJ/package.json"
touch "$PROJ/tsconfig.json"
OUT=$(printf '{"cwd":"%s"}' "$PROJ" | bash "$HOOK" 2>/dev/null)
echo "$OUT" | grep -q "systemMessage" && pass || fail "no systemMessage for new stack dir"
rm -rf "$PROJ"
teardown_test_home

begin_test "cwd-changed: includes stack info in message"
setup_test_home
PROJ=$(mktemp -d)
echo '{"dependencies":{"react":"18.0.0"},"devDependencies":{"typescript":"5.0.0"}}' > "$PROJ/package.json"
touch "$PROJ/tsconfig.json"
OUT=$(printf '{"cwd":"%s"}' "$PROJ" | bash "$HOOK" 2>/dev/null)
echo "$OUT" | grep -qi "TypeScript\|React" && pass || fail "stack not in message"
rm -rf "$PROJ"
teardown_test_home

begin_test "cwd-changed: no output for empty directory"
setup_test_home
PROJ=$(mktemp -d)
OUT=$(printf '{"cwd":"%s"}' "$PROJ" | bash "$HOOK" 2>/dev/null)
[ -z "$OUT" ] && pass || fail "should produce no output for empty dir"
rm -rf "$PROJ"
teardown_test_home

begin_test "cwd-changed: no output when stack unchanged (cached)"
setup_test_home
PROJ=$(mktemp -d)
echo '{"dependencies":{"react":"18.0.0"}}' > "$PROJ/package.json"
# First run — primes cache
printf '{"cwd":"%s"}' "$PROJ" | bash "$HOOK" >/dev/null 2>/dev/null || true
# Second run — same dir, same stack
OUT=$(printf '{"cwd":"%s"}' "$PROJ" | bash "$HOOK" 2>/dev/null)
[ -z "$OUT" ] && pass || fail "should not re-emit for unchanged stack"
rm -rf "$PROJ"
teardown_test_home

begin_test "cwd-changed: detects Python stack"
setup_test_home
PROJ=$(mktemp -d)
echo "django==5.0" > "$PROJ/requirements.txt"
OUT=$(printf '{"cwd":"%s"}' "$PROJ" | bash "$HOOK" 2>/dev/null)
echo "$OUT" | grep -qi "Python\|Django" && pass || fail "Python stack not detected"
rm -rf "$PROJ"
teardown_test_home

begin_test "cwd-changed: no output for malformed input"
OUT=$(printf '{}' | bash "$HOOK" 2>/dev/null)
[ -z "$OUT" ] && pass || fail "should produce no output for empty input"

unset SUPERCHARGER_NO_DEDUP
report
