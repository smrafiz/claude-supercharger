# Known Issues

Status: **4 open** · Last updated: 2026-08-25 · Opened against v2.29.22

Defects that are diagnosed but not fixed. Each entry carries a reproduction and the
evidence behind the diagnosis, so the next session can act without re-deriving it.
Per-release history lives in [`../CHANGELOG.md`](../CHANGELOG.md); this file is only
for what is currently broken.

| # | Issue | Severity | Blocks |
|---|---|---|---|
| 1 | `test-e2e-integration.sh` fails on a clean working tree | high | CI on a fresh clone |
| 2 | `release.sh` gates on a dirty tree | high | trustworthy release gating |
| 3 | `claim-evidence-gate` matches substrings, not verdicts | medium | agent self-reporting |
| 4 | `base64 -d` is still a bare-substring rule | low | scanner signal rate |

---

## 1 — `test-e2e-integration.sh` fails on a clean working tree

**Symptom.** `tests/run.sh` reports `3888 passed, 1 failed`, exit 1. The failure is
`tests/test-e2e-integration.sh:85` — *"checkpoint contains files list"*.

**Root cause.** The test builds a `FAKE_HOME` and a temp project, but
`hooks/session-checkpoint.sh` shells out to git and resolves to the **enclosing real
repository** rather than the payload `cwd`. The `files:` field is emitted only when git
reports modified files (`hooks/session-checkpoint.sh:128`), so on a clean tree the field
is absent and the assertion fails. The `branch:` field is the tell — a bare temp dir
would have produced no branch either.

**Reproduction.** Nothing varies but the working tree:

```
clean tree              → FAIL  checkpoint contains files list
one untracked scratch   → PASS
```

**Not a regression.** Present before v2.29.22. Verified across three consecutive
full-suite runs.

**Proposed fix.** Resolve the project root from the payload `cwd` instead of inheriting
git's discovery. Touches a hot-path hook, so it wants its own release.

**Do not** diagnose this by running `test-e2e-integration.sh` standalone. Standalone does
not reproduce `run.sh`'s environment and yields a different failure count (2 at v2.29.21,
1 at v2.29.22) that means nothing. Only full-suite runs are valid signal.

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
