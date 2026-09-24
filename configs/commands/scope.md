Pre-flight scope check before starting: $ARGUMENTS

Do NOT start implementation. This is a planning gate: it fixes exactly what will change, what that touches, where the work stops, and then waits for approval.

Siblings: `/estimate` sizes work before deciding to do it (ranges, reference class); `/challenge` stress-tests a hard-to-reverse decision. This command owns the file list, the blast radius and the finish line — not time estimates.

Design sources: Claude Code plan mode (catching "this is used in 12 places" before the edit), GitHub Spec Kit and AWS Kiro specs (acceptance criteria and a definition of done per task), Google design docs (non-goals), change-impact / blast-radius analysis, and the agent evidence that the most common failure is completing the authorized task plus unrequested extra changes.

**Evidence rule:** every file in the inventory comes from a search or read done this session (`rg`, `git grep`, opening the file) and is marked KNOWN. A file you believe is involved but have not confirmed is marked ASSUMED. Agent file lists written from memory are routinely wrong.

**Step 0 — Route**
- **Small** — one or two files, easy to undo. Run Steps 1, 2, 4 and 7.
- **Large** — several files, or anything hard to undo (schema or data migration, public API or wire format, auth, CI/CD, deletions, new dependencies). Run every step.

**Step 1 — Task and definition of done**
Restate the task in one sentence. Then write 1–3 acceptance criteria as **Given / When / Then** — the observable finish line. Without one, the work does not know when to stop.

**Step 2 — File inventory**
Every file to create, modify or delete: path · what changes (one sentence) · KNOWN or ASSUMED.

**Step 3 — Blast radius**
For each modified function, type, config key or file: its direct callers and dependents (`rg` / `git grep` the changed symbol) and the tests that cover it. Name what changes with **no** test covering it — that is where a regression will land unnoticed.

**Step 4 — Non-goals and minimal diff**
- **Non-goals**: things that could reasonably be part of this task but will NOT be done — "not refactoring the handler", "not fixing the unrelated lint", "not upgrading the library". Each one is a commitment the implementation is held to.
- **Minimal diff**: the smallest change that meets the definition of done.

**Step 5 — Reversibility and review triggers**
Mark each change easy or hard to undo. Hard-to-undo changes, and anything touching a schema, auth, a public API, CI/CD, a deletion or a new dependency, need explicit human sign-off — list them. For a hard-to-undo decision that is still contested, run `/challenge` before approving.

**Step 6 — Assumptions and risks**
The assumptions the plan rests on. If one of them would change the file list and the context cannot settle it, ask exactly one question before presenting the gate. Then 2–3 specific risks — each names a mechanism, a trigger and a component, not a category.

**Step 7 — Approval gate**
Present the scope, with a one-line rollback plan, and wait for approval. Do not begin implementation until approved. Once approved, anything outside the inventory or on the non-goals list needs a new approval.

**Output format:**
```
TASK: [one sentence] · ROUTE: [small | large]
DONE WHEN:
  Given [...] When [...] Then [...]

FILES:
  Create: [path] — [what] — [KNOWN | ASSUMED]
  Modify: [path] — [what] — [KNOWN | ASSUMED]
  Delete: [path] — [why] — [KNOWN | ASSUMED]

BLAST RADIUS: [changed symbol] → callers: [...] · tests: [...] · NOT covered: [...]

NON-GOALS: [...]
MINIMAL DIFF: [...]

REVERSIBILITY: [easy | HARD: which change] · needs sign-off: [schema / auth / API / CI / delete / dependency | none]
ASSUMPTIONS: [...]
RISKS:
  1. [mechanism] — trigger: [...] — in: [component] — mitigation: [...]
ROLLBACK: [how to undo]

Proceed? (waiting for approval)
```
