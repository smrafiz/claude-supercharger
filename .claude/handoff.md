# Handoff — claude-supercharger

The project's carry file: **one per project, tracked in git, read first by a fresh
session on any machine.**

### Current State
*Verified 2026-11-25 ~19:00, session `c7ed25f1`.*

- **Released: v4.4.9.** Master `e8f75d76` (= #366 + #367). NOT released: #366, and #368 once merged. Release on hold (user).
- **Open PR #368** `fix/guard-gaps-2` HEAD `df519430`: not merged. At last look ubuntu + macOS suites were PENDING, Windows dispatch 45616838013 queued. An earlier dispatch (45607193376 on 1989a3e7) had ubuntu FAIL, cause unread: check first. Local full suite on df519430 never finished: rerun unpiped.
- **Side repo:** `smrafiz/readback` PRIVATE, main `bfd6de7` (workflow, rule, skills, plugin + install.sh). Before public: the user's live plugin-hook test + GitHub render check.
- **Queue (Sonnet build, Opus review):** batch-editor haiku->sonnet PR (`configs/agents/batch-editor.md`); Fable guard + statusline; compaction standing rules; input-size cap for >128KB commands (pre-existing fail-open); workflow integration into Supercharger (needs approval). Memory: `project-state-2026-11-25-end`.
- **Rules:** Sonnet builds, Opus reviews/plans/research; never Fable unless asked; no worktrees; no Artifacts; never `git checkout` during a background suite; merge only when nothing is pending, on the user's word.
- **Per-machine (work Mac):** only bash is 3.2.57; global rule `~/.claude/rules/workflow.md` installed here.

### Log
#### 2026-11-25 (deep) — c7ed25f1
Built and 3x Opus-reviewed guard-gaps-2 (PR #368, round 3 no MUST); researched the best workflow and shipped it as the private `readback` repo (plugin + install.sh, 3 review rounds). Builder looped 3h on the suite (stopped).
Detail: `.claude/handoff-c7ed25f1-03ea-465a-820d-7e75d4eaf0d9.md`

#### 2026-11-24 — c7ed25f1
Audited boxdawn/guard, built + Opus-reviewed + merged #366 (review caught 2 fail-open defects we introduced).
Windows needed a test fix (plain quoted rm is allowed on Git Bash). Memory pass done.
Detail: `.claude/handoff-c7ed25f1-03ea-465a-820d-7e75d4eaf0d9.md`

### Per-machine / per-account facts
- **Worktrees are per-machine.** `.claude/worktrees/` is not in git. On 2026-11-03 this machine had
  none of the four the previous brief listed; recreate from `origin/<branch>`. On 2026-11-07 this machine
  has no extra worktrees, only the `master` branch and 0 stashes (cleaned this session).
- **This session's machine (2026-10-30):** 0 stashes, no extra worktrees, Caveman active (it elides
  tool output lines). The "4 stashes on Machine A" earlier note was not seen here.
- **`claude-supercharger` is PUBLIC — its Actions are free and unmetered.**
  Sept usage: Windows 10,678 min, macOS 1,977, Linux 3,652, **all netting $0.00**.
  Windows is trending hard: Jul 166 → Aug 7,744 → Sep 10,678.
- **`smrafiz/radius-apps` Actions were DISABLED 2026-09-22** over a quota email —
  but it does **not appear in the billing usage at all**. Re-enable when
  convenient; with Actions off, its PRs merge with no CI. Billing cycle is
  calendar-month, resets **2026-10-01**.
- `radiustheme/radius-bundles` is an ORG repo, billed separately, already tuned.

### Decisions parked, not blocked
- **Default-branch prompt stays on** for this repo (user, 2026-11-01): no `allowDefaultBranchCommits`.
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

#### 2026-11-23 (deep) — eaedd321
Merged #357, #359–#363: download ledger ASK, git-safety fail-closed, model-ask guard (Fable), detector
stdin on Windows. 4.4.9 held to 2026-11-24. Two self-caused suite invalidations (checkout mid-run).
Detail: `.claude/handoff-eaedd321-5e4c-41af-80ed-a51a6c772596.md`

#### 2026-11-22 (deep) — eaedd321
Reviewed #341–#353 (3 agents): 3 HIGH, ~8 MED; fixed and merged as #354–#356 (+ Windows-only fixes).
#358 docs merged. #357 perf-chain flake open. Item 5 (cross-command download ASK) drafted on wip branch.
Detail: `.claude/handoff-eaedd321-5e4c-41af-80ed-a51a6c772596.md`

#### 2026-11-20 — e23c930b
Merged #341, #344–#346, #348–#352. Plan Step 3 gaps 1–7 done except the cross-command form
of gap 1. Master CI green throughout; one macOS capacity cancel, one Windows shard timeout (rerun green).
Detail: `.claude/handoff-e23c930b-242b-4a70-ad35-626553c9e4dd.md`
