# Handoff — claude-supercharger

The project's carry file: **one per project, tracked in git, read first by a fresh
session on any machine.**

### Current State
*Verified 2026-11-22, session `eaedd321`.*

- **Released: v4.4.8.** 4.4.9 is **held**: the user said release after a speed re-measure on a quiet
  machine (load was 70–315 all day on 2026-11-22, so no reliable numbers yet). Release only then.
- **Master `b6682009`, CI green** incl. Windows. Open: **#357** (perf-chain test fork-count fallback,
  test-only). No worktrees. Per-machine: the work machine has 6 old stashes, not ours; never pop.
- **A review of #341–#353 found 3 HIGH, ~8 MED bugs; all fixed and merged:** #354 (slow glob = fail-open,
  notebook Read unscanned, `claude plugin disable` variants, download-then-run spellings), #355 (#346
  regression, #341 bypasses, `.pub`-first, pip config/env forms, mshta/Zone.Identifier, reworded
  injections), #356 (#351 runners, #353 cd-dir/triggers/FIFO/64 KB/dedupe, config-scan wording).
- **Speed re-measure (item 3):** `safety.sh` on `ls -la src` read 23–28 ms on master vs 33–41 ms after
  #354 under load. Compare v4.4.8 vs master on a quiet machine before releasing.
- **Next:** cross-command download-then-run, design in `docs/CROSS-COMMAND-DOWNLOAD-RUN-DESIGN.md`,
  two open questions for the user (ASK vs deny; does a Read clear it). Build on their word.
- **Step 5 confirmed by the user 2026-11-22:** Edit/Write of guard code/tests after a pattern-text deny is OK.
- **Merging:** `gh pr merge N --squash --delete-branch --match-head-commit <sha>`; dispatch
  `gh workflow run ci.yml --ref <b>` (PR CI skips Windows) and check master's post-merge CI.
- **Releasing:** `release.sh stage X.Y.Z --message ... --yes`, wait for rel CI, `release.sh promote X.Y.Z --yes`.
- **No Artifacts** (user): plans go in `docs/*.md`.

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

#### 2026-11-22 — eaedd321
Reviewed #341–#353 (3 agents): 3 HIGH, ~8 MED; fixed and merged as #354–#356 (Windows-only fixes on #355
pip path, #356 cd target). Opened #357 (perf-chain load flake). Wrote cross-command download-run design.
Detail: `.claude/handoff-eaedd321-5e4c-41af-80ed-a51a6c772596.md`

#### 2026-11-20 — e23c930b
Merged #341, #344–#346, #348–#352. Plan Step 3 gaps 1–7 done except the cross-command form
of gap 1. Master CI green throughout; one macOS capacity cancel, one Windows shard timeout (rerun green).
Detail: `.claude/handoff-e23c930b-242b-4a70-ad35-626553c9e4dd.md`

#### 2026-11-19 (deep) — eaedd321
Merged #335–#339 and #342 (symlink targets, managed MCP allowlist, claim-gate reviewer, compress
negations, credential-read gaps A, review-prompt rules). Audits: avhn/secret, agent-white-hat (replays),
vantage, Agasthy and four more. B/C open; plan in docs/GUARD-GAP-PLAN-2026-11-19.md.
Detail: `.claude/handoff-eaedd321-5e4c-41af-80ed-a51a6c772596.md`

#### 2026-11-18 — eaedd321
Reviewers found fail-opens in #325/#326/#329; fixed, then merged #324–#333 and released v4.4.8.
New: #331 `>|` in 4 guards, #332 disk-watch `$(( ))` code exec, #333 safety.sh fail-closed + `--build-arg`.
Detail: `.claude/handoff-eaedd321-5e4c-41af-80ed-a51a6c772596.md`

#### 2026-11-18 (deep) — c03df59e
Reviewed tsrmehmet/memokit (MIT) by replaying 701 of its fixtures through our Bash chain. Opened
#325 (7 gaps, 2 FPs), #326 approval codes, #327 disk-watch, #328 office-read, #329 quoted-pipe FP.
Three Windows-only failures found and fixed. Nothing merged.
Detail: `.claude/handoff-c03df59e-1112-4fd1-b43d-e88dec9ea249.md`
