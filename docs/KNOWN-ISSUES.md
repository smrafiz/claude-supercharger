# Known Issues

Status: **3 open** · Last updated: 2026-08-25 · Opened against v2.29.22 · #1 fixed in v2.29.24

Defects that are diagnosed but not fixed. Each entry carries a reproduction and the
evidence behind the diagnosis, so the next session can act without re-deriving it.
Per-release history lives in [`../CHANGELOG.md`](../CHANGELOG.md); this file is only
for what is currently broken.

| # | Issue | Severity | Blocks |
|---|---|---|---|
| ~~1~~ | ~~`test-e2e-integration.sh` fails on a clean working tree~~ | ~~high~~ | **fixed v2.29.24** |
| 2 | `release.sh` gates on a dirty tree | high | trustworthy release gating |
| 3 | `claim-evidence-gate` matches substrings, not verdicts | medium | agent self-reporting |
| 4 | `base64 -d` is still a bare-substring rule | low | scanner signal rate |

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

## 2 — `release.sh` gates on a dirty working tree

**Symptom.** Issue 1 has never blocked a release, despite failing on any clean checkout.

**Root cause.** `tools/release.sh` runs the suite *before* it commits, so the tree always
carries the release's own uncommitted changes at the moment tests execute. Any test whose
outcome depends on repo cleanliness is therefore evaluated under conditions that never
match CI or a fresh clone.

**Consequence.** The test count written into each CHANGELOG entry is measured under those
same conditions. The v2.29.22 entry reads *"3889 tests passing"*; a clean checkout of that
same commit reports 3888 passed, 1 failed.

**Proposed fix.** Run the gating suite against a clean checkout — a temporary worktree at
the candidate commit is the cheapest route and needs no change to the tests themselves.

---

## 3 — `claim-evidence-gate` matches substrings, not verdicts

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

**Proposed fix.** Anchor the evidence scan on the fail marker rather than the word, and
skip claim sentences carrying a negation.

---

## 4 — `base64 -d` is still a bare-substring rule

**Location.** `hooks/bash-injection-scanner.sh`, patterns panel.

v2.29.22 tightened the one bare-noun rule in that panel to require an instruction-shaped
construction. `base64 -d` is the remaining rule that matches a token rather than an
instruction, and is the same class of false positive: it fires on ordinary output that
mentions the command.

Lower blast radius than the rule already fixed, because the panel scans command *output*
rather than the command itself, so incidental hits are rarer. Same trade-off applies —
tightening reduces catch rate on naive payloads.
