# Handoff — claude-supercharger

The project's carry file: **one per project, tracked in git, read first by a fresh
session on any machine.**

### Current State
*Verified 2026-10-01 12:35 UTC, session `3d213381`.*

- **Released: v4.1.25.** v4.1.26 (#85 PowerShell output scanning, #86 elicitation
  trust + URL checks) is STAGED (rel/4.1.26 CI green) and a detached job
  (`.claude/worktrees/tmp/rel4126.sh`, log `rel4126.out`, per-machine A) promotes
  it once master's Windows run for 515f900 is green, then runs update.sh.
- **Open PRs, green, NOT merged:** #88 ShareOnboardingGuide secret scan, #89
  env-exec-guard PowerShell `$env:`. Merge only AFTER v4.1.26 promotes (promote
  fast-forwards master; any merge before it makes promote refuse). Auto mode
  refused scheduling these merges unattended: merge by hand.
- **Machine A:** installed 4.1.25 at 12:33; a `sog` stash entry duplicates #88, drop it.
- **Machine B**: unknown. Update to the latest release.
- **Open**: classifierContext needs a measured sync path; redirect-clobber-guard
  PowerShell (deferred); radius-apps guard-push wrapper bypass; rotate CRON_SECRET.

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

#### 2026-09-30 (evening) — 3d213381
A 7-minute branch debug run found fp-triage's Windows cause (backslash hook
path) and a cross-OS secret-masking gap; fixed in #82, verifying on Windows.
Detail: `.claude/handoff-3d213381-9717-4755-b743-9b2b101ebce9.md`

#### 2026-09-30 (late) — 3d213381
v4.1.23 out after three Windows refusals (MSYS paths, hidden failure text). Input
budget built and used: 38.3 -> 27.6 KB per session here. Manual Windows CI trigger
added; fp-triage Windows debug in flight.
Detail: `.claude/handoff-3d213381-9717-4755-b743-9b2b101ebce9.md`

#### 2026-09-30 — 3d213381
Released v4.1.19-22: router and prompt hooks stop reading harness text as user
text, agent hint removed (1.1% uptake), block-ledger secret masking. Built
fp-triage, fixed selfmod FPs. Found the CI test gate green-on-failure since
09-16. Jev researched and parked.
Detail: `.claude/handoff-3d213381-9717-4755-b743-9b2b101ebce9.md`

