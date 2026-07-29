#!/usr/bin/env bash
# Claude Supercharger — Test Integrity Guard
# Event: PreToolUse | Matcher: Edit, MultiEdit, Write
#
# Defends the Verification Gate ("run tests, confirm they pass"): the one way an
# agent games it is by editing the TESTS instead of fixing the code — adding
# skip/only markers (it.skip, describe.only, @pytest.mark.skip, @Ignore, t.Skip,
# xit, #[ignore]) or deleting assertions so a broken suite goes green. This ASKS
# the user to confirm when an edit to a test file removes assertions or introduces
# skip/only markers. The closest existing hooks (lazy-refactor-check,
# comment-replacement-check) inspect param/comment churn, not test semantics.
# Advisory + fail-open; disable with SUPERCHARGER_TEST_INTEGRITY_GUARD=0.
set -uo pipefail
HOOKS_DIR="${BASH_SOURCE[0]%/*}"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh" 2>/dev/null || true

[ "${SUPERCHARGER_TEST_INTEGRITY_GUARD:-1}" = "0" ] && exit 0

_INPUT=$(cat)
check_hook_disabled "test-integrity-guard" 2>/dev/null && exit 0

# v2.24.2: fork-free gate — see package-source-guard for the rationale. Every branch
# of the python's is_test check requires the literal "test" or "spec" somewhere in the
# path (.test. / _spec. / test_*.py / __tests__/ / …), so requiring one of those in the
# raw payload is a strict superset: a gate miss cannot skip a real test file, and a
# spurious hit just runs the unchanged python.
case "$_INPUT" in
  *test*|*Test*|*TEST*|*spec*|*Spec*|*SPEC*) : ;;
  *) exit 0 ;;
esac

REASON=$(printf '%s\n' "$_INPUT" | python3 -c '
import sys, os, json, re

try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)

tool = d.get("tool_name") or ""
if tool not in ("Edit", "MultiEdit", "Write"):
    sys.exit(0)

inp = d.get("tool_input") or {}
fp = inp.get("file_path") or ""
if not fp:
    sys.exit(0)
name = os.path.basename(fp)
low = name.lower()
fpl = fp.lower()

# ── Test-file gate ────────────────────────────────────────────────────────────
# Common conventions across ecosystems + directory hints. Deliberately specific
# so ordinary source files never trip; a miss only means we skip (fail-open).
is_test = bool(
    re.search(r"(\.test\.|\.spec\.|_test\.|_spec\.|\.tests\.)", low)
    or re.search(r"^test_.*\.py$", low)
    or re.search(r"(test|tests|spec)\.[jt]sx?$", low)
    or re.search(r"(test|tests)\.java$", low)
    or re.search(r"_spec\.rb$|_test\.rb$", low)
    or re.search(r"_test\.go$", low)
    or re.search(r"(/|^)(__tests__|tests?|spec)(/|$)", fpl)
)
if not is_test:
    sys.exit(0)

# ── Signal regexes ────────────────────────────────────────────────────────────
# Skip / focus markers: skip disables a test; only/f-prefix focuses THIS test and
# thereby disables its siblings — both game the suite.
SKIP_RE = re.compile(
    r"\b(?:it|test|describe|context|specify|beforeEach)\.(?:skip|only)\b"
    r"|\bx(?:it|describe|test|context|specify)\b"
    r"|\bf(?:it|describe)\b"
    r"|@pytest\.mark\.skip|@pytest\.mark\.skipif|@unittest\.skip\w*"
    r"|@(?:Ignore|Disabled)\b"
    r"|\bt\.Skip(?:Now)?\b"
    r"|#\[ignore\]"
    r"|\.skip\(|\.only\("
    r"|\bpending\b|\bxspecify\b"
)
# Assertion tokens across ecosystems. Relative count only (old vs new), so a
# slightly loose token that appears equally in both is harmless.
ASSERT_RE = re.compile(
    r"\bexpect\s*\(|\bassert\w*|\bshould\b"
    r"|\.(?:toBe|toEqual|toStrictEqual|toMatch|toContain|toThrow|toHaveBeen\w*|resolves|rejects)\b"
    r"|\bEXPECT_[A-Z]|\bASSERT_[A-Z]|\bXCTAssert\w*"
    r"|\brequire\.(?:Equal|NoError|True|False|Nil|NotNil|Len|Contains)\b"
)

def counts(text):
    if not text:
        return (0, 0)
    return (len(ASSERT_RE.findall(text)), len(SKIP_RE.findall(text)))

# ── Build (old, new) text pairs ───────────────────────────────────────────────
pairs = []
if tool == "Edit":
    pairs.append((inp.get("old_string") or "", inp.get("new_string") or ""))
elif tool == "MultiEdit":
    for e in (inp.get("edits") or []):
        pairs.append((e.get("old_string") or "", e.get("new_string") or ""))
elif tool == "Write":
    # Full overwrite — compare against the on-disk version if it exists. A brand
    # new test file (no prior) is legitimate authoring, not gaming → skip.
    new = inp.get("content")
    if new is None:
        sys.exit(0)
    try:
        with open(fp, "r", errors="replace") as f:
            old = f.read()
    except Exception:
        sys.exit(0)  # no prior file → new authoring
    pairs.append((old, new))

asserts_removed = 0
skips_added = 0
for old, new in pairs:
    oa, osk = counts(old)
    na, nsk = counts(new)
    if na < oa:
        asserts_removed += (oa - na)
    if nsk > osk:
        skips_added += (nsk - osk)

if not asserts_removed and not skips_added:
    sys.exit(0)

bits = []
if skips_added:
    bits.append("adds %d skip/only marker(s)" % skips_added)
if asserts_removed:
    bits.append("removes %d assertion(s)" % asserts_removed)
print(
    "Test-integrity: this edit to %s %s. "
    "Editing the test to pass (skipping it or deleting assertions) defeats the "
    "Verification Gate rather than fixing the code under test. Confirm this is an "
    "intentional test change, not a way to make a failing suite go green."
    % (name, " and ".join(bits))
)
' 2>/dev/null)

[ -z "$REASON" ] && exit 0

RSN=$(printf '%s' "$REASON" | jq -Rs '.' 2>/dev/null || printf '"%s"' "$REASON")
printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":%s}}\n' "$RSN"
echo "[Supercharger] test-integrity-guard: ASK on test edit" >&2
exit 0
