Run a multi-lens review by dispatching parallel specialist agents: $ARGUMENTS

Finders fan out across lenses; a SEPARATE, fresh-context verifier then tries to refute every serious finding; only what survives is reported. Findings raised by 2+ lenses are highest priority.

Design sources: Anthropic's managed Code Review (finders → independent verification → dedupe/rank, pre-existing bucket), `/code-review` (effort dial), `claude-code-security-review` (confidence ≥ 8/10, hard exclusions), Refute-or-Promote (arXiv 2604.19049: an adversarial refuter lifts precision), Greptile model-inversion (a model under-detects the bug classes it authors — so verifiers never see the finder's reasoning).

**Step 1 — Parse arguments and target**

- Effort: a leading `quick`, `standard` or `deep` in $ARGUMENTS. Default `standard`.
- Target: the rest of $ARGUMENTS — file path, PR number, branch, or description. If empty, the current branch diff against the default branch (`git diff $(git merge-base HEAD origin/HEAD)...HEAD`, falling back to `main`/`master`).
- Skip file classes outright: lockfiles, generated/vendored code, build output, snapshots, minified assets, and anything CI lint already enforces.
- If the remaining diff is under ~50 changed lines, drop to `quick` — fan-out overhead is not worth it on a small diff.

**Step 2 — Build the shared brief (once, reused by every agent)**

1. The diff, plus for each changed hunk its **enclosing function and direct callers** — findings are judged on surrounding code, not the hunk alone.
2. Project rules: `CLAUDE.md` and `REVIEW.md` if present (repo root and the changed directories).
3. The **finding contract** every finder must follow:
   - `file:line` citation of code it actually READ, plus the quoted line. A claim inferred from a name or signature is not a finding.
   - A concrete failure scenario: which input or state produces which wrong result, crash, leak or exploit.
   - `introduced` (this diff adds or changes the faulty line) or `pre-existing`.
   - Severity MUST FIX / SHOULD FIX, and confidence 0–100.
   - **Signal filter — do NOT report:** denial-of-service / resource exhaustion, rate-limiting gaps, open redirects, generic "missing input validation" with no demonstrated path, style a formatter would fix, or anything confidence < 60.
   - Read, don't run: no builds, tests or network calls. Read-only git (`log`, `blame`, `show`) is allowed.

**Step 3 — Dispatch finders in parallel** (read-only reviewer agents — the Critic agent where installed, otherwise general-purpose; one message, all at once)

| Lens | quick | standard | deep |
|---|---|---|---|
| **Security** — injection, authz gaps, credential exposure, unsafe shell/eval, secrets, insecure defaults, trust-boundary validation | ✓ one combined reviewer covers every lens | ✓ | ✓ |
| **Correctness** — logic errors, edge cases (empty, null, unicode, concurrency, partial failure), error handling that loses data, API misuse, off-by-one, contract changes that break callers | | ✓ | ✓ |
| **Performance** — N+1, blocking I/O on hot paths, work inside loops, unbounded growth, quadratic string/collection ops | | ✓ | ✓ |
| **Tests & conventions** — new logic with no test, assertions that pass against broken code, tests of a mock instead of the code, explicit `CLAUDE.md`/`REVIEW.md` rule violations (flag only when the rule text names the issue; also flag docs the diff makes stale) | | ✓ | ✓ |
| **History & design** — `git log`/`git blame` on changed lines: does this revert a deliberate earlier fix or re-introduce a removed pattern? Coupling, layering, a fix applied at one caller when the shared function owns the bug | | | ✓ |

Each brief names its lens and tells the agent to stay inside it; boundary bugs still leak, so dedupe in Step 5.

**Step 4 — Independent adversarial verification** (the orchestrator does NOT verify its own findings)

Send every MUST FIX, and every SHOULD FIX with confidence ≥ 80, to fresh verifier agents — `standard`: one verifier for the whole batch; `deep`: one verifier per MUST FIX. A verifier receives ONLY the claim, the `file:line`, and the brief from Step 2 — never the finder's reasoning. Its instruction: **try to prove the finding wrong.** Read the code and answer:

- **REACHABILITY** — can this run with caller- or attacker-controlled input, or is it dead, guarded or test-only?
- **IMPACT** — name the concrete harm. No nameable harm → not a MUST FIX.
- **DEFENSES** — does an existing check, type, framework guarantee or caller contract already neutralize it?

Verdict: **CONFIRMED** (keeps severity) · **DOWNGRADE** (reachable, but impact uncertain or partially defended — one tier down) · **REFUTED** (dropped, one line in *Filtered*). `quick` has no separate verifier: the single reviewer applies the same three questions to its own MUST FIX list and must mark them `self-verified`.

**Step 5 — Dedupe, rank, cap**

1. Merge findings that cite the same `file:line` or the same root cause; record every lens that raised it. 2+ lenses → **Cross-lens**.
2. Final gate: report only confidence ≥ 80 (`quick`, `standard`) or ≥ 60 (`deep`).
3. `pre-existing` findings go to their own section — never mixed with what this diff introduced.
4. Cap SHOULD FIX at 8 listed; report the remainder as a count.

**Step 6 — Report**

```
## Multi-Lens Review: [target] — effort: [quick|standard|deep]

### Verdict: [Ready to merge | Fix MUST FIX first | Needs rework]

### Cross-Lens Findings (highest confidence)
### MUST FIX (introduced by this change)
- [file:line] — claim · failure scenario · lenses · confidence · CONFIRMED/DOWNGRADE
  <details>How verified: reachability / impact / defenses in one line each</details>
### SHOULD FIX (top 8; +N more)
### Pre-existing (not introduced here — worth a separate ticket)
### Filtered (refuted by verification)
- claim — why (unreachable / no impact / already defended)

### Coverage
- Lenses run: [...] · Files reviewed: N · Skipped (generated/lockfile/vendored): N
- MUST FIX: N confirmed · SHOULD FIX: N · Pre-existing: N · Refuted: N
```

If nothing survives verification, say so plainly — an empty review is a valid outcome, not a failure to pad.
