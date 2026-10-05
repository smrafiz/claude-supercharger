# Handoff — claude-supercharger

The project's carry file: **one per project, tracked in git, read first by a fresh
session on any machine.**

### Current State
*Verified 2026-10-05 evening, session `3d213381`.*

- **Released: v4.1.30** (installed on Machine A). master = 50405e3 (#97 + #98, all of v4.2.0).
- **In flight: v4.2.0 release**, detached on Machine A: `release.sh stage minor` then
  `.claude/worktrees/tmp/finish420.sh` (waits rel/4.2.0 CI + master Windows, promotes, update.sh).
  Logs: .claude/worktrees/tmp/{stage420,finish420,promote420}.log. Verify: `gh release view v4.2.0`.
  Do NOT merge to master until promoted (the ff promote refuses).
- **Unpushed:** branch docs/handoff-2026-10-05b (this handoff + HOOK_AUTHORING notes). Push + PR
  after 4.2.0 is promoted.
- **Machine A:** many redundant worktrees under .claude/worktrees/; stash `sog` (user's to delete).
- **Machine B**: unknown. **Open (user)**: radius-apps guard-push wrapper; rotate CRON_SECRET.

### Per-machine / per-account facts
- **`claude-supercharger` is PUBLIC — its Actions are free and unmetered.**
  Sept usage: Windows 10,678 min, macOS 1,977, Linux 3,652, **all netting $0.00**.
  Windows is trending hard: Jul 166 → Aug 7,744 → Sep 10,678.
- **`smrafiz/radius-apps` Actions were DISABLED 2026-09-22** over a quota email —
  but it does **not appear in the billing usage at all**. Re-enable when
  convenient; with Actions off, its PRs merge with no CI. Billing cycle is
  calendar-month, resets **2026-10-01**.
- `radiustheme/radius-bundles` is an ORG repo, billed separately, already tuned.

### Decisions parked, not blocked
- **Install the tag rather than master?** Merging to master currently IS
  shipping. Against: users lose immediate fixes. Mitigating: PRs run all 8 jobs.
- **Never seize the output-style slot.** One global field; `force-for-plugin`
  overrides the user's own choice.

### Open, not started
- **What is actually at 90%?** Every billing line nets $0.00 yet the email fired.
  The included-minutes counter is not exposed by the API — read the Billing page.
- **An unexplained deny.** A `sensitive file access` block fired on a commit
  command, unreproduced in five attempts. If it recurs, capture the command first.
- **Stacked PRs**: merging a parent and deleting its branch CLOSES the child.
---

## Log

#### 2026-10-05 (evening) — 3d213381
Batch 4 merged (#98, 50405e3) after fixing 3 tests (2 test bugs, 1 real crontab separator gap
present since v4.1.17); suite 6212/0. v4.2.0 staging/promoting detached.
Detail: `.claude/handoff-3d213381-9717-4755-b743-9b2b101ebce9.md` (Status — evening)

#### 2026-10-05 — 3d213381
v4.1.30 out (#93 #94 #96). Four research rounds -> #97 (v4.2.0 features) merged; batch 4
(FP audit fixes, CI/GitHub, infra coverage, docs) on feat/batch4, 3 tests to fix, then ship 4.2.0.
Detail: `.claude/handoff-3d213381-9717-4755-b743-9b2b101ebce9.md`

#### 2026-10-04 — 3d213381
v4.1.26-4.1.29 out. Real-payload hook replay found 3 size-dependent slowdowns
(#91 quadratic brace count, #92 per-line forks); path-guard 3->1 python (#93,
staged as 4.1.30); PowerShell clobber coverage (#94, open).
Detail: `.claude/handoff-3d213381-9717-4755-b743-9b2b101ebce9.md`

#### 2026-10-01 (pm) — 3d213381
v4.1.26 staged, promote pending master Windows. #88 guards ShareOnboardingGuide
(uploads ./ONBOARDING.md, schema read from the CC binary); #89 env-exec-guard
PowerShell. Coverage-diff #12 (LSP) closed as no-leak.
Detail: `.claude/handoff-3d213381-9717-4755-b743-9b2b101ebce9.md`

#### 2026-10-01 — 3d213381
v4.1.24 and v4.1.25 out. Coverage diff vs CC 2.1.286 found PowerShell output and
elicitation gaps (#85, #86, pending). Skills list was the largest context cost;
Shopify skills moved into their projects.
Detail: `.claude/handoff-3d213381-9717-4755-b743-9b2b101ebce9.md`
