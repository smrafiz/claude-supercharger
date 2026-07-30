#!/usr/bin/env bash
# Suite-count invariance (v2.24.12)
#
# The README tests-badge check in tests/run.sh compares the suite total EXACTLY and
# fails in CI. That is only sound while the total is the same everywhere. It wasn't:
# CI was red for six consecutive releases (2.24.6 → 2.24.10) because two tests put
# their assertion INSIDE an availability gate, so where the tool was missing the
# assertion did not run — it ceased to exist:
#
#   test-post-write-advisor.sh  broken/valid toml   gated on python3 tomllib (>=3.11)
#   test-plugin-hooks.sh        claude plugin validate   gated on the claude CLI
#
# ubuntu counted 2608, macOS 2607, and one badge number cannot satisfy both.
#
# The rule enforced here: an availability gate may skip the WORK, but it must still
# report the assertion. Concretely — if a gated block emits assertions, it needs an
# `else` branch (which is where the skip gets reported). A gate that only selects an
# expected VALUE is fine and must not be flagged; test-mcp.sh's HAS_GH does exactly
# that, and an earlier heuristic of mine false-positived on it.
#
# Assertion COUNTS are deliberately not compared: helpers such as `check` emit
# assertions without a literal begin_test, so counting is unreliable. Presence of an
# else branch is the property that actually prevents an assertion from vanishing.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

echo "=== Suite Count Invariance Tests ==="

SCAN=$(cat <<'PY'
import re, sys, glob, os

# Conditions that depend on the MACHINE rather than on test data.
AVAIL = re.compile(r'command -v|\bwhich\s|\bHAS_[A-Z0-9_]+\b|-x\s+["$/]|import\s+tomllib')
# Lines that cause an assertion to be reported. `check`/assert_* are local helpers
# that call begin_test internally, so a literal begin_test is not required.
EMITS = re.compile(r'\bbegin_test\b|^\s*check\s+|\bassert_[a-z_]+\s')

# Heredoc bodies are DATA, not control flow. Test files embed shell fixtures via
# `cat > f <<'EOS'` (this file included), and parsing those as live `if` blocks
# reports the fixture instead of the code under test.
# Quote chars as \x27/\x22: an unbalanced literal quote inside this heredoc breaks
# bash 3.2's $( ) parser (it matches quotes/parens through a quoted heredoc body).
HEREDOC = re.compile(r'<<-?\s*[\x27\x22]?([A-Za-z_][A-Za-z0-9_]*)[\x27\x22]?')

problems = []
for path in sorted(glob.glob(os.path.join(sys.argv[1], 'tests', 'test-*.sh'))):
    lines = open(path, errors='replace').read().split('\n')
    stack = []
    heredoc_end = None
    for i, raw in enumerate(lines, 1):
        s = raw.strip()
        if heredoc_end is not None:
            if s == heredoc_end:
                heredoc_end = None
            continue
        if s.startswith('#'):
            continue
        m = HEREDOC.search(raw)
        if m:
            heredoc_end = m.group(1)
            continue
        # A complete one-line `if … fi` cannot hide an assertion from one platform
        # while showing it on another in a way an else branch would fix.
        oneline = s.startswith('if ') and re.search(r'(^|;|\s)fi\s*$', s)
        if s.startswith('if ') and not oneline:
            stack.append({'avail': bool(AVAIL.search(s)), 'emits': False,
                          'has_else': False, 'line': i})
            continue
        if re.match(r'^(else\b|elif\b)', s) and stack:
            stack[-1]['has_else'] = True
            continue
        if re.match(r'^fi\b', s) and stack:
            fr = stack.pop()
            if fr['avail'] and fr['emits'] and not fr['has_else']:
                problems.append('%s:%d' % (os.path.basename(path), fr['line']))
            # An inner block's assertions belong to the enclosing block too.
            if stack and fr['emits']:
                stack[-1]['emits'] = True
            continue
        if EMITS.search(raw) and stack:
            stack[-1]['emits'] = True

print('\n'.join(problems))
PY
)

begin_test "no availability gate hides an assertion (needs an else that reports the skip)"
PROBLEMS=$(python3 -c "$SCAN" "$REPO_DIR" 2>&1)
if [ -z "$PROBLEMS" ]; then
  pass
else
  fail "gated assertions with no else branch (count varies by machine): $(printf '%s' "$PROBLEMS" | tr '\n' ' ')"
fi

# Guard the guard: it must actually flag the two shapes that broke CI, or it is
# decoration. Reconstructs them rather than trusting that it would have caught them.
begin_test "the checker flags a tool-gated assertion with no else"
TD=$(mktemp -d); mkdir -p "$TD/tests"
cat > "$TD/tests/test-fixture-bad.sh" <<'EOS'
if command -v claude >/dev/null 2>&1; then
  begin_test "validator runs"
  pass
fi
EOS
OUT=$(python3 -c "$SCAN" "$TD" 2>&1)
printf '%s' "$OUT" | grep -q 'test-fixture-bad.sh' && pass || fail "checker missed the regression shape"

begin_test "the checker flags a HAS_* gated assertion with no else"
cat > "$TD/tests/test-fixture-has.sh" <<'EOS'
if [ "$HAS_TOML" = 1 ]; then
  check "broken toml"  WARN .toml 644 'x'
fi
EOS
OUT=$(python3 -c "$SCAN" "$TD" 2>&1)
printf '%s' "$OUT" | grep -q 'test-fixture-has.sh' && pass || fail "checker missed the HAS_* shape"

begin_test "the checker accepts a gate that reports the skip in an else"
rm -f "$TD/tests/test-fixture-bad.sh" "$TD/tests/test-fixture-has.sh"
cat > "$TD/tests/test-fixture-good.sh" <<'EOS'
begin_test "validator runs"
if command -v claude >/dev/null 2>&1; then
  pass
else
  echo "    (skipped: claude CLI not installed)"
  pass
fi
EOS
OUT=$(python3 -c "$SCAN" "$TD" 2>&1)
[ -z "$OUT" ] && pass || fail "false positive on a correctly-reported skip: $OUT"

begin_test "the checker ignores a gate that only selects an expected value"
rm -f "$TD/tests/test-fixture-good.sh"
cat > "$TD/tests/test-fixture-value.sh" <<'EOS'
if [ "$HAS_GH" = "yes" ]; then EXPECTED=4; else EXPECTED=3; fi
begin_test "mcp: server count matches role"
[ "$TOTAL" = "$EXPECTED" ] && pass || fail "count"
EOS
OUT=$(python3 -c "$SCAN" "$TD" 2>&1)
[ -z "$OUT" ] && pass || fail "flagged a value-only gate (test-mcp.sh's shape): $OUT"
rm -rf "$TD"

report
