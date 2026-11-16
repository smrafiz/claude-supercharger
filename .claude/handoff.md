# Handoff — claude-supercharger

The project's carry file: **one per project, tracked in git, read first by a fresh
session on any machine.**

### Current State
*Verified 2026-11-16, session `c8c4db43`.*

- **Released: v4.4.6** (2026-11-13). **Master `bc85c97b`** carries #302-#316 unreleased.
  Release **held by the user** (4.4.7 on their word only).
- **Merged today:** #315 (PR A, shell/-c/trap/git/xargs) and #316 (PR B, git/interpreter/env).
- **Open: #317** (PR C, dropper/metadata/interp-fetch/unshare; N2 dropped by the user), head
  376e92b3; full CI run 43864806536 was running at handoff. Merge with `--match-head-commit`.
- **Local-only branches on the session machine (not pushed):** `fix/sc-security-scanner-fp`
  c7103a5d (the /sc-security skill-scan FP: shipped-hash manifest, CRLF, 5 tests) and
  `perf/normalize-c-locale` 95346e9a (`LC_ALL=C` in normalize_cmd; speedup unmeasured). Both
  are on old master dd9a77d9: rebase, run the suite, open a PR, dispatch CI.
- **No worktrees** (all removed 2026-11-16 at the user's request).
- **Upstream:** anthropics/claude-code#110181 (project `disableAllHooks`).
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

#### 2026-11-16 (deep) — c8c4db43
Finished the cc-safety-net A/B/C PRs: merged #315 and #316, opened #317. A 10k transcript replay
caught 9 real-work FPs the tests missed; two quadratic hot-path steps fixed (344 s, 4-14 s). N2 dropped.
Detail: `.claude/handoff-c8c4db43-9e98-47e4-b1fc-0bcb9b1b8de6.md`

#### 2026-11-15 (deep) — 104cfc73
cc-safety-net delta audit: 20 bypasses of our rules + 3 new classes; fixes split into three WIP
branches (A/B/C), pushed at shutdown, no PRs. Posted anthropics/claude-code#110181.
Detail: `.claude/handoff-104cfc73-8853-40b7-9d59-e1f2d891a351.md`

#### 2026-11-15 — 74e29661
Merged #307–#311 and #313 (#310 closed a real `git --config-env` bypass; #313 rules line). Live-tested
project `disableAllHooks` (kills all our hooks) and hook `if` filters (miss env/command/bash -c).
Detail: `.claude/handoff-74e29661-88dc-4f1d-b9dd-a17f876352b7.md`

#### 2026-11-14 — e7f6ce82
Reviewed kintsugi-harness, Nodrail agent-plugins and agent-guard by probing their scenarios
against our hooks. Merged #302–#306 (Bidi, code patterns, update-check stdout, vacuous test,
Grep wildcard globs); #307 (kubectl/mvn/Read parity) open. Release held.
Detail: `.claude/handoff-e7f6ce82-f0ce-4e41-957d-c06160b73ecb.md`

#### 2026-11-13 (deep) — 00ecfc20
Merged #299; master went red on the ubuntu-26.04 image switch. Root cause: timing EXIT trap
rewrote a deny (exit 2) to exit 1 on an unwritable audit dir — fixed in #301. Released v4.4.6.
Detail: `.claude/handoff-00ecfc20-17c7-4686-8d8f-3c1c1b36af96.md`
