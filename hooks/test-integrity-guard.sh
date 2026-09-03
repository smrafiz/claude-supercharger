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
#
# v4.0.25 adds the sibling arm: weakening the LINTER instead of fixing the code.
# test-mask-guard covers the command channel (`npm test || true`), this hook
# covered the test file, and the rules the check runs under were guarded nowhere.
# Count-deltas only — a rule switched off, or enforced rules dropped — so adding a
# rule, reformatting or bumping a version stays silent. Disable that arm alone:
# SUPERCHARGER_LINT_CONFIG_GUARD=0
# Disable: SUPERCHARGER_TEST_INTEGRITY_GUARD=0
set -uo pipefail
HOOKS_DIR="${BASH_SOURCE[0]%/*}"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh" 2>/dev/null || true

[ "${SUPERCHARGER_TEST_INTEGRITY_GUARD:-1}" = "0" ] && exit 0

# v2.26.35: fork-free stdin read. `$(cat)` forks /bin/cat in EVERY hook —
# ~1.8ms each, and 18 blocking hooks fire per Bash tool call. The trailing
# strip reproduces $(cat)'s newline handling so this is byte-identical.
IFS= read -r -d '' -t "${SUPERCHARGER_STDIN_TIMEOUT_S:-5}" _INPUT || [ $? -le 128 ] || _INPUT=""; _INPUT="${_INPUT%"${_INPUT##*[!$'\n']}"}"
check_hook_disabled "test-integrity-guard" 2>/dev/null && exit 0

# v2.24.2: fork-free gate — see package-source-guard for the rationale. Every branch
# of the python's is_test check requires the literal "test" or "spec" somewhere in the
# path (.test. / _spec. / test_*.py / __tests__/ / …), so requiring one of those in the
# raw payload is a strict superset: a gate miss cannot skip a real test file, and a
# spurious hit just runs the unchanged python.
# v4.0.25 adds the lint-config arm, so the gate has to admit those filenames too —
# an arm whose payload never reaches the python is dead code its own tests still
# pass ([[two-gate-trap]]). nocasematch for the reason v4.0.24 folded the other
# guards: `.ESLintRC.json` is the same file as `.eslintrc.json` on APFS/NTFS.
_TIG_NOCASE=$(shopt -p nocasematch 2>/dev/null || true)
shopt -s nocasematch 2>/dev/null || true
case "$_INPUT" in
  *test*|*spec*) _TIG_HIT=1 ;;
  *eslintrc*|*eslint.config*|*prettierrc*|*prettier.config*|*biome.json*|*ruff.toml*|\
  *.flake8*|*stylelintrc*|*stylelint.config*|*markdownlint*|*tsconfig*|*golangci*|\
  *.rubocop.yml*|*.pylintrc*|*setup.cfg*|*.shellcheckrc*) _TIG_HIT=1 ;;
  *) _TIG_HIT=0 ;;
esac
eval "$_TIG_NOCASE" 2>/dev/null || true
[ "$_TIG_HIT" = "1" ] || exit 0

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
# ── Lint/formatter-config gate ────────────────────────────────────────────────
# The sibling channel of the same defect. Editing the TEST to pass is guarded
# above; editing the LINTER so the check stops complaining was not guarded
# anywhere -- test-mask-guard covers the command (`npm test || true`),
# test-integrity-guard covered the test file, and the rules the check runs under
# were the arm nobody wrote (cross-channel-parity-drift, again).
#
# Matched on the lowercased name for the v4.0.24 reason: .ESLintRC.json is the
# same file on APFS/NTFS. pyproject.toml is deliberately absent -- it carries
# dependencies and project metadata beside the linter section, so edits to it are
# overwhelmingly not lint changes.
is_lint = bool(
    re.search(r"^\.?eslintrc(\.|$)|^eslint\.config\.[cm]?[jt]s$", low)
    or re.search(r"^\.?prettierrc(\.|$)|^prettier\.config\.[cm]?[jt]s$", low)
    or low in ("biome.json", "biome.jsonc", "ruff.toml", ".ruff.toml", ".flake8",
               ".pylintrc", ".rubocop.yml", ".shellcheckrc", "setup.cfg")
    or re.search(r"^\.?stylelintrc(\.|$)|^stylelint\.config\.[cm]?js$", low)
    or re.search(r"^\.?markdownlint(-cli2)?(\.|rc$)", low)
    or re.search(r"^tsconfig(\.\w+)?\.json$", low)
    or re.search(r"^\.golangci\.(yml|yaml|toml|json)$", low)
)

if not is_test and not is_lint:
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

# ── Lint-config signals ───────────────────────────────────────────────────────
# Deliberately count-DELTAS, like the test arm above, not "this file was touched".
# Their equivalent hook denies every edit to an existing lint config; editing an
# eslint config is ordinary work, and a guard that fires on ordinary work is one
# people switch off. Reformatting, adding a rule, bumping a version: all silent,
# because the counts do not move.
#
# DISABLE_RE rising  => a rule was switched off, or a blanket disable added.
# ENABLED_RE falling => rules were deleted or downgraded out of enforcement.
DISABLE_RE = re.compile(
    r"[\"\x27]off[\"\x27]"
    r"|\beslint-disable(?:-next-line|-line)?\b"
    r"|#\s*noqa\b"
    r"|//\s*prettier-ignore\b"
    r"|#\s*type:\s*ignore\b"
    # TS strictness is a boolean, so the weakening direction differs per key:
    # strict flags turned off, escape hatches turned on.
    r"|[\"\x27](?:strict|noImplicitAny|strictNullChecks|strictFunctionTypes"
    r"|noUnusedLocals|noUnusedParameters|alwaysStrict|noImplicitReturns)[\"\x27]\s*:\s*false"
    r"|[\"\x27](?:skipLibCheck|allowJs|ignoreDeprecations)[\"\x27]\s*:\s*true"
)
# A rule that is still enforced: eslint/stylelint severities as strings, or the
# numeric 1/2 forms. Counting these makes a DELETED rule show up as a drop, which
# a disable-token scan alone cannot see.
#
# NOTE: no literal apostrophes anywhere in this python — it is embedded in a
# python3 -c \x27...\x27 shell string, and one would end it mid-script. \x27 is
# the apostrophe to the regex engine and inert to the shell.
ENABLED_RE = re.compile(
    r"[\"\x27](?:error|warn)[\"\x27]"
    r"|^\s*-\s*\w[\w/-]*\s*$"
    , re.M)
# Numeric severities (0/1/2) are an ESLint/Stylelint spelling, and only there is a
# bare 1 or 2 a rule. Counting them everywhere read prettier\x27s "tabWidth": 2 -> 4
# as a dropped rule -- a formatting width is not enforcement. Found by probing the
# arm against ordinary config edits before writing any test for it.
NUMERIC_SEVERITY_RE = re.compile(r":\s*[12]\s*(?:[,}\]]|$)", re.M)
numeric_severities = bool(
    re.search(r"^\.?eslintrc(\.|$)|^eslint\.config\.", low)
    or re.search(r"^\.?stylelintrc(\.|$)|^stylelint\.config\.", low)
)

def lint_counts(text):
    if not text:
        return (0, 0)
    enabled = len(ENABLED_RE.findall(text))
    if numeric_severities:
        enabled += len(NUMERIC_SEVERITY_RE.findall(text))
    return (enabled, len(DISABLE_RE.findall(text)))

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

if is_lint and os.environ.get("SUPERCHARGER_LINT_CONFIG_GUARD", "1") != "0":
    rules_dropped = 0
    disables_added = 0
    for old, new in pairs:
        oe, od = lint_counts(old)
        ne, nd = lint_counts(new)
        if ne < oe:
            rules_dropped += (oe - ne)
        if nd > od:
            disables_added += (nd - od)
    if rules_dropped or disables_added:
        bits = []
        if disables_added:
            bits.append("switches %d rule(s) off" % disables_added)
        if rules_dropped:
            bits.append("drops %d enforced rule(s)" % rules_dropped)
        print(
            "Lint-config: this edit to %s %s. "
            "Weakening the linter is the sibling of editing the test to pass — the "
            "check goes green without the code being fixed. Confirm this is an "
            "intentional config change. Silence: SUPERCHARGER_LINT_CONFIG_GUARD=0"
            % (name, " and ".join(bits))
        )
    sys.exit(0)

if not is_test:
    sys.exit(0)

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
case "$REASON" in
  Lint-config:*) echo "[Supercharger] test-integrity-guard: ASK on lint-config edit" >&2 ;;
  *)             echo "[Supercharger] test-integrity-guard: ASK on test edit" >&2 ;;
esac
exit 0
