# Handoff — claude-supercharger

The project's carry file: **one per project, tracked in git, read first by a fresh
session on any machine.**

### Current State
*Verified 2026-10-08, session `3d213381`.*

- **Released: v4.3.0** (2026-10-08; installed on Machine A). Contains #102 (4.2.1: notify
  duration fix, Windows drive-letter rm, PowerShell .NET delete), #103 (all commands renamed
  `sc-<name>` + migration, command frontmatter, 19 user-only commands, macOS notifier app),
  301e3a0 (CRLF redirect-stub fix, pushed direct to master — origin unknown), #104 (README
  complete through 4.3.0), #105 (notifier app is opt-in: install asks [y/N], updates never
  build it, `/sc-notifier`).
- **Open PR #106:** `/sc-profile` help counts 7/10 (was 8/11) + this carry-file update.
- **Next:** quote/escape decode in the command normalizer, then ssh/sed-e bodies (write as
  one-rule Edit edits — memory: classifier-stops-guard-patches). Then `!` live context in
  sc-status/perf/why (test the not-allowlisted behaviour first).
- **Watch:** 4.3.0 migration on colleagues' machines (stubs, "you edited it" notices); 4.2.0
  asks (npm publish, foreign-owner push, trace deletion) for false positives.
- **Release recipe:** `release.sh stage minor --yes --message "..."` detached, then
  `promote X.Y.Z --yes`, then update.sh. `gh run watch` returns early — poll `gh run view`.
  A failed stage can leave a LOCAL `rel/X.Y.Z` branch: delete it before re-staging.
- **Machine A:** stashes `osc-notify-default-4.3.0`, `aborted-stage-4.3.0-bump`, `sog`
  (all safe to drop; user's call). Notifier app NOT installed (removed for the update test).
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

#### 2026-10-08 — 3d213381
4.2.1 + 4.3.0 shipped: notification never fired (Stop payload has no cost field), commands
renamed sc- with hash-checked migration, frontmatter/user-only commands, opt-in macOS
notifier app (consent fix after user flagged silent install). No per-session brief written.

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

