#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

HOOK="${FOCUSED_TEST_HOOK:-$REPO_DIR/hooks/commit-guard.sh}"

echo "=== commit-guard: focused test in the staged diff ==="
export SUPERCHARGER_NO_DEDUP=1
setup_test_home

_verdict() { # <file> <line> -> ask | deny | allow
  local d out; d=$(mktemp -d)
  ( cd "$d" && git init -q && git checkout -q -b feat/x && mkdir -p "$(dirname "$1")" && printf '%s\n' "$2" > "$1" && git add -A )
  out=$(printf '{"tool_name":"Bash","tool_input":{"command":"git commit -m \\"fix: x\\""},"cwd":"%s"}' "$d" | bash "$HOOK" 2>/dev/null)
  rm -rf "$d"
  case "$out" in *'"ask"'*) echo ask ;; *'"deny"'*) echo deny ;; *) echo allow ;; esac
}

_case() { # <want> <file> <line>
  begin_test "focused test: $2 :: $3 -> $1"
  local got; got=$(_verdict "$2" "$3")
  [ "$got" = "$1" ] && pass || fail "want $1, got $got"
}

_case ask   src/login.test.ts      'it.only("works", () => {})'
_case ask   src/login.spec.js      '  describe.only("x", () => {'
_case ask   src/__tests__/a.js     'fit("x", () => {})'
_case ask   e2e/a.spec.ts          'test.describe.only("x", async () => {})'
_case ask   src/a.test.tsx         'fdescribe ("x", () => {})'
_case allow src/login.test.ts      'it("works", () => {})'
_case allow src/login.ts           'it.only("x")'
_case allow src/login.test.ts      'const benefit = profit(3)'
_case allow src/login.test.ts      '// avoid it.only in commits'
_case allow tests/test-x.sh        'it.only('

teardown_test_home
report
