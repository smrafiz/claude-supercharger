# Handoff — claude-supercharger

The project's carry file: **one per project, tracked in git, read first by a fresh
session on any machine.**

### Current State
*Verified 2026-10-07, session `3d213381`.*

- **Released: v4.2.0** (2026-10-07T03:14:45Z; installed on Machine A). master = a618ba8.
  Contains #97 #98 #99 #100 (sweep 5).
- **Open PR #101:** this docs branch (handoffs + HOOK_AUTHORING notes). Docs only.
- **Next (4.2.1):** list in PR #100 body — general quote/escape decode, ssh/sed-e bodies,
  Windows C:/Users targets + [IO.*]::Delete, Bash allowed_domains. Write as small one-rule
  Edit-tool edits (see memory: classifier-stops-guard-patches).
- **Watch:** new asks in 4.2.0 (npm publish, foreign-owner push, trace deletion, Mod warning)
  for false positives in real use.
- **Release recipe:** `release.sh stage minor --yes --message "..."` detached, then
  `promote X.Y.Z --yes`, then update.sh. `echo y |` does NOT work.
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

#### 2026-10-06 — 3d213381
#99 fixed master Windows (CR-CR-LF). Sweep 5 (4 research agents) -> PR #100: normalizer
bypasses, FPs, Mods/Artifact/token/remote coverage. Classifier cut many patch turns.
Detail: `.claude/handoff-3d213381-9717-4755-b743-9b2b101ebce9.md` (2026-10-06 deep)

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
