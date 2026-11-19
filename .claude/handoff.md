# Handoff — claude-supercharger

The project's carry file: **one per project, tracked in git, read first by a fresh
session on any machine.**

### Current State
*Verified 2026-11-19, session `eaedd321`.*

- **Released: v4.4.8.** 4.4.9 is **held by the user** (#335–#339, #342 merged on master; B and C to
  join). Release only on the user's word.
- **Open PRs:** #340 (B, credential printers + env dumps) rebased on master after #339, pushed with
  `--force-with-lease` at `88650ec9`: local full suite 8548 passed / 0 failed; Windows run
  44506111356 dispatched (check it before merging).
  #341 (C) conflicts with master: rebase after B merges.
- **Next work:** `docs/GUARD-GAP-PLAN-2026-11-19.md` (steps 1–5). Step 2 is a confirmed BROKEN
  guard: start there after B and C.
- **No worktrees, no stash.** Switch branches in the main checkout. Per-machine: the work machine has
  6 old stashes that are not this session's; never pop them.
- **No Artifacts** (user, 2026-11-19): plans go in `docs/*.md`.
- **Merging:** `gh pr merge N --squash --delete-branch --match-head-commit <full sha>`.
- **Releasing:** `release.sh stage X.Y.Z --message ... --yes`, wait for rel CI, then
  `release.sh promote X.Y.Z --yes`.

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

#### 2026-11-17 (deep) — c8c4db43
Merged #319–#323: skill-scan FP, LC_ALL=C normalize (≈40% faster), container bind-mount rm deny,
/sc-security chains, /sc-health allowManagedHooksOnly. Seven repo audits. 4.4.8 held by the user.
Detail: `.claude/handoff-c8c4db43-9e98-47e4-b1fc-0bcb9b1b8de6.md`

#### 2026-11-16 (deep) — c8c4db43
Finished the cc-safety-net A/B/C PRs: merged #315 and #316, opened #317. A 10k transcript replay
caught 9 real-work FPs the tests missed; two quadratic hot-path steps fixed (344 s, 4-14 s). N2 dropped.
Detail: `.claude/handoff-c8c4db43-9e98-47e4-b1fc-0bcb9b1b8de6.md`
