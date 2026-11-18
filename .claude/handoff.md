# Handoff — claude-supercharger

The project's carry file: **one per project, tracked in git, read first by a fresh
session on any machine.**

### Current State
*Verified 2026-11-18, session `eaedd321`.*

- **Released: v4.4.8** (2026-11-18, tag on `68071b2a`): #319–#333. Nothing unreleased; no open PRs;
  master = `68071b2a`, CI green incl. Windows.
- **Now in master:** the approval gate (#326; the user types `approve <code>` or `approve <code> 30m`, a window
  over 4h is clamped with a notice); safety.sh fails closed on its own crash (#333); `>|` denied in 4 guards (#331).
- **Known limits:** a crash inside lib-timing/lib-paths before safety.sh installs its trap relies on
  `onFailure`; variable-built paths bypass string-matching guards; the office-read cache is never evicted.
- **No worktrees.** The user asked (2026-11-18): switch branches in the main checkout instead.
  (Session eaedd321 missed this line and used worktrees throughout; read this file first.)
- **Open questions:** quoted remote bodies (`ssh host '…|sh'`, `watch`, `tmux send-keys`,
  `script -c`) are allowed on master — design question, not started. office-read tested only with a
  fake markitdown.
- Per-machine: eaedd321's machine install is **v4.4.7**, so run `/sc-update`.
- **Releasing:** `release.sh stage X.Y.Z --message ... --yes`, wait for rel CI, then
  `release.sh promote X.Y.Z --yes`.
- **Merging:** `gh pr merge N --squash --delete-branch --match-head-commit <full sha>`.
- **Open:** risk-review log ~2026-11-20; FP audit re-run ~2026-12-08; SpecLock (parked).

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

#### 2026-11-15 (deep) — 104cfc73
cc-safety-net delta audit: 20 bypasses of our rules + 3 new classes; fixes split into three WIP
branches (A/B/C), pushed at shutdown, no PRs. Posted anthropics/claude-code#110181.
Detail: `.claude/handoff-104cfc73-8853-40b7-9d59-e1f2d891a351.md`
