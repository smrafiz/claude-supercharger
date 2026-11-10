# Handoff — claude-supercharger

The project's carry file: **one per project, tracked in git, read first by a fresh
session on any machine.**

### Current State
*Verified 2026-11-10, session `104cfc73`.*

- **Released: v4.4.5** (2026-11-08), tag on `bda06a90`. This machine (per-machine) runs 4.4.5.
- **Master `5bdf4689`** (#280 merged; PR run green on 12 jobs). Branch
  `fix/sensitive-read-commit-prose` open: commit-message prose with `;`/`|` inside the quotes
  was scanned as a command (b495e37d); output-secrets-scanner wakes the parent once per
  subagent, not per hit (4b034d8f). PR after the full suite.
- **4.4.6 HELD** (user, 2026-11-09): #264–#280 merged and unreleased. Release only on their word.
- **#277–#280:** prompt/env allowlists (+README), handback FPs 10→6, test-mask dedup,
  direnv files on Read/Grep/Glob, `whsec_`/`glpat-`/`shp*_` token formats (phantom-secrets delta;
  its proxy/vault design is off-thesis). applygate delta closed (#274–#276).
- **Next:** release 4.4.6 on the user's word; `/sc-security` recall test (planted vulns) if wanted.
  Skipped by decision: an audit step in /sc-security (no network, version currency excluded).
- `/sc-security` HAS run on a real repo: radius-bundles 2026-11-01, 0 findings, honest gaps.
- Per-machine: 6 stashes (incl. `3d45886a`) are the user's to drop; a stash/pop probe popped it by
  mistake 2026-11-10, restored, stash kept; branch `feat/supply-chain-gaps`.
- `test-perf-chain` statusline timing flakes under suite load (passes alone).
- **Releasing:** `release.sh stage X.Y.Z --message ... --yes` (background); stage skips its gate
  when master CI is green on HEAD; promote needs Windows green on master's base commit.
- **Merging:** `gh pr merge N --squash --delete-branch --match-head-commit <full sha>`.
- **Open:** risk-review log ~2026-11-20; re-run the FP audit a month after 4.4.5; SpecLock
  (parked); economy re-measure. Handback replay done 2026-11-10 (#277).

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

#### 2026-11-10 — 104cfc73
Merged #274-#280: ReDoS, .claude dir, cluster identity flags + tfstate, prompt/env allowlists,
README, direnv + token formats (phantom-secrets delta). Handback replay: 3 of 5 refusals were FPs.
Open branch: commit-prose separator FP + one subagent notice. 4.4.6 still held.
Detail: this entry (no separate brief).

#### 2026-11-09 (deep) — 104cfc73
Merged #267-#273: pulumi/gh global opts, pool runner, eksctl ask, detector budget pin, statusline
autoCompactWindow, nested-run home sweep (master red → green). Open: #274 ReDoS guard hang, #275
.claude dir guard. 4.4.6 held.
Detail: `.claude/handoff-104cfc73-8853-40b7-9d59-e1f2d891a351.md`

#### 2026-11-08 (deep) — 78fcacce
Released v4.4.5 after #263 (release.sh gated on the wrong workflow). Merged #264 (OSV malware deny)
and #265 (config-scan outward allows), release held. Both turned master Windows red: undiagnosed.
Detail: `.claude/handoff-78fcacce-5d1c-41b5-940b-c12ac8d016cb.md`

#### 2026-11-05 → 11-08 (deep) — 1c2a497d
Released v4.4.4 (#239-#249). Merged #250-#262: update check, commit-check `-F`, batch-editor, risk
review, host-contract suite, handback/pipe/dotenv/password-reset FP fixes, commit-hash citation warning,
global options before a subcommand (found via applygate). Guard FP audit: 62% FP. 4.4.5 staged.
Detail: `.claude/handoff-1c2a497d-cf2e-47c6-b04d-a1f84d704781.md`

#### 2026-11-04 (deep) — 3d213381
Merged #241-#244 (cloud-cli asks, claim gate stale/zero-test, supply-chain asks, paste overrun,
tamper chmod). Found Stop/SubagentStop notes reach nobody; subagents need a PreToolUse deny on
SubagentHandback. #245 does that and retires subagent-stop-check (merged 2026-11-05).
Detail: `.claude/handoff-3d213381-9717-4755-b743-9b2b101ebce9.md`


