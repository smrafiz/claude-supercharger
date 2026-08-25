# Known Issues

Status: **0 open** · Last updated: 2026-08-25 · Opened against v2.29.22 · all four fixed: #1 v2.29.24, #4 v2.29.25, #2 v2.29.26, #3 v2.29.27

Defects that are diagnosed but not fixed. Each entry carries a reproduction and the
evidence behind the diagnosis, so the next session can act without re-deriving it.

**Nothing is currently open.** Every entry below is closed; they are kept for the
reproductions and for the bug classes they name, not as outstanding work.
Per-release history lives in [`../CHANGELOG.md`](../CHANGELOG.md); this file is only
for what is currently broken.

| # | Issue | Severity | Blocks |
|---|---|---|---|
| ~~1~~ | ~~`test-e2e-integration.sh` fails on a clean working tree~~ | ~~high~~ | **fixed v2.29.24** |
| ~~2~~ | ~~`release.sh` gates on a dirty tree~~ | ~~high~~ | **fixed v2.29.26** |
| ~~3~~ | ~~`claim-evidence-gate` matches substrings, not verdicts~~ | ~~medium~~ | **fixed v2.29.27** |
| ~~4~~ | ~~`base64 -d` is still a bare-substring rule~~ | ~~low~~ | **fixed v2.29.25** |

---

## 1 — `test-e2e-integration.sh` fails on a clean working tree — FIXED v2.29.24

**Outcome.** Clean checkout went from `3893 passed, 1 failed` to
`3894 passed, 0 failed`. Same tree state, measured before and after.

**The root cause recorded here was WRONG.** This entry originally blamed
`hooks/session-checkpoint.sh` for resolving to the enclosing repository instead of
the payload `cwd`, and proposed changing that hook — one that fires on every
Write/Edit/Bash — noting it "wants its own release". The hook was never broken. It
calls `git -C cwd` throughout and honours the payload correctly; an exact
replication of the test setup, including the fresh `HOME` that `run.sh` imposes,
passed.

**Actual cause.** `tests/test-e2e-integration.sh` keeps its own `result()` /
`PASS_COUNT` machinery and therefore never sourced `tests/helpers.sh` — which left
`native_path()` undefined in that file:

```
native_path undefined  →  $(native_path "$PROJ") == ""
                       →  payload carries "cwd":""
                       →  hook falls back to os.getcwd()  (this repo, master, clean)
                       →  no modified files  →  no files: field  →  assertion fails
```

**The tell was `branch:master`.** Every temp repo the test builds reports
`branch:main`, because `run.sh` gives each file a fresh `HOME` so git never sees a
user `init.defaultBranch`. A checkpoint naming `master` could only have come from
this repository. After the fix it reads `branch:main commits:<sha>:chore: init`.

**Fix.** One `source` line. The counters are namespaced differently
(`TESTS_PASSED` vs `PASS_COUNT`), so nothing collides.

**Lesson worth keeping.** A wrong diagnosis in this file is more costly than none:
it pointed at a hot-path hook and carried enough detail to look settled. Reproduce
before acting on an entry here, and treat a field that names the *wrong repository*
as a cwd-resolution question rather than a git-discovery one.

---

## 2 — `release.sh` gates on a dirty working tree — FIXED v2.29.26

**Symptom.** Issue 1 has never blocked a release, despite failing on any clean checkout.

**Root cause.** `tools/release.sh` runs the suite *before* it commits, so the tree always
carries the release's own uncommitted changes at the moment tests execute. Any test whose
outcome depends on repo cleanliness is therefore evaluated under conditions that never
match CI or a fresh clone.

**Consequence.** The test count written into each CHANGELOG entry is measured under those
same conditions. The v2.29.22 entry reads *"3889 tests passing"*; a clean checkout of that
same commit reports 3888 passed, 1 failed.

**Fixed in v2.29.26.** The gate now builds a temporary detached worktree at `HEAD`,
mirrors the working tree onto it (deletions, modifications, and untracked-but-not-ignored
files), commits that state so the checkout is clean, and runs the suite there. The
worktree is removed on exit, including on interrupt.

What gets gated is the tree that is about to be **committed**: `release.sh` stages with
`git add -A`, so untracked files are part of the candidate and are mirrored too. Ignored
files are not, which is the point.

Verified behaviourally rather than by inspection — the fixture's suite fails if the tree
it runs in is dirty *and* fails if an untracked candidate file is missing, so one test
proves both halves. Against the pre-fix script it fails with `the gate still ran in the
dirty working tree`. `--dry-run` exits before the gate, so it never pays for a worktree.

Escape hatch: `SUPERCHARGER_RELEASE_GATE_INPLACE=1` restores the old in-place behaviour,
and the gate falls back to in-place with a warning if the worktree cannot be created.

---

## 3 — `claim-evidence-gate` matches substrings, not verdicts — FIXED v2.29.27

**Symptom.** The gate fires on statements that are not passing claims.

**Observed twice, both false positives:**

- Cited `PASS pytest FAILED markers are detected` as evidence of failure. That is a green
  line whose *test name* contains "FAILED".
- Fired on the sentence *"…is accurate the way it was measured, and wrong in a clean
  checkout"* — a sentence explicitly disclaiming the quoted figure.

**Root cause.** Both the evidence scan and the claim scan key on substrings without
checking whether the surrounding line is a pass or a fail, or whether the claim is being
asserted or negated.

**Why it matters.** A gate that fires on correct reporting trains the reader to dismiss
it, which costs exactly the signal the gate exists to provide. Note the gate was
*substantively right* on the second firing — the suite did fail — which is what makes the
false-positive mechanism easy to overlook.

**Fixed in v2.29.27**, both halves separately.

*Evidence scan.* Failure detection now runs per line and treats a line whose own verdict
marker is `PASS`/`OK`/`✓` as green regardless of what its test NAME contains. ANSI is
stripped first — the suite colours its markers, so a prefix match would otherwise never
fire. This was worse than recorded: `FAIL_UPPER` matched `FAILED` inside the name on this
repo's own green line, so a run reporting **0 failures** was read as failing, not merely
mis-quoted.

*Claim scan.* A new `DISCLAIM` pattern sits beside the existing `HEDGE` one. `HEDGE`
covers conditionals ("once tests pass"); `DISCLAIM` covers retractions ("wrong",
"inaccurate", "no longer", "does not hold").

Both exemptions are bounded by an anti-bypass test: a red run containing `PASS` lines
still blocks, and a retraction in one sentence does not excuse an unhedged claim in the
next. Of the 5 new assertions, 3 fail against the pre-fix hook; the other 2 are those
anti-bypass guards, which pass on both sides by design — an exemption test that failed
before the exemption existed would be testing the wrong thing.

---

## 4 — `base64 -d` is still a bare-substring rule — FIXED v2.29.25

**Location.** `hooks/bash-injection-scanner.sh`, patterns panel.

v2.29.22 tightened the one bare-noun rule in that panel to require an instruction-shaped
construction. `base64 -d` is the remaining rule that matches a token rather than an
instruction, and is the same class of false positive: it fires on ordinary output that
mentions the command.

Lower blast radius than the rule already fixed, because the panel scans command *output*
rather than the command itself, so incidental hits are rarer.

**Reproduced live.** Reading this file tripped the scanner, and the entry being read was
this one — the defect documented its own occurrence.

**Fixed in v2.29.25.** The rule now requires the decode to be piped into a shell, which is
the point at which decoded bytes actually execute. Bisected against the pre-fix hook; 5 of
the 7 new assertions in `tests/test-bash-injection-scanner.sh` fail without the change.

The predicted trade-off above did **not** materialise — catch rate went *up*, not down.
The old rule was the literal string `base64 -d`, so it never matched `--decode` at all:

| payload | pre-fix | post-fix |
|---|---|---|
| `-d` piped to `sh` | flagged | flagged |
| `--decode` piped to `bash` | **missed** | **flagged** |
| `-d` piped to `zsh` | flagged | flagged |
| three prose/doc mentions | **flagged** (FP) | clean |
| this file's own text | **flagged** (FP) | clean |

Net: one payload class gained, four false positives dropped, no regression. The accepted
cost is unchanged from v2.29.22's — a two-step payload that decodes to a file and runs it
separately no longer matches *this* rule, and is left to the instruction-shaped rules.
