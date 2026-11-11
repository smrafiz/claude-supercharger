# Handoff — claude-supercharger

The project's carry file: **one per project, tracked in git, read first by a fresh
session on any machine.**

### Current State
*Verified 2026-11-11, session `104cfc73`.*

- **Released: v4.4.5** (2026-11-08), tag on `bda06a90`. This machine (per-machine) runs 4.4.5.
- **Master `16ee990c`**: #282-#288 merged 2026-11-11; CI + Host contract green on it.
- **Open, not merged:** #289 (secret dirs on Read; .azure, pass store, sops age key) CI run
  43016837281; #290 (GIT_CONFIG_PARAMETERS/GIT_PROXY_COMMAND/GIT_EXEC_PATH/ZDOTDIR) CI run
  43019899100. Merge each when its dispatched ci.yml is 12/12 green.
- **4.4.6 HELD** (user): #264-#288 merged and unreleased (+#289/#290 once merged). Release only on their word.
- **Delta audits closed:** cc-audit (#285/#286/#287) and aidevops (#289/#290). Parked by the user:
  variable-as-command-name (`x=rm; $x -rf /`). Unchecked: aidevops's prompt-injection patterns, `GOCSPX-`.
- Per-machine: 6 stashes (incl. `3d45886a`) are the user's; branch `feat/supply-chain-gaps`.
- **Releasing:** `release.sh stage X.Y.Z --message ... --yes` (background); stage skips its gate
  when master CI is green on HEAD; promote needs Windows green on master's base commit.
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

#### 2026-11-11 (deep) — 104cfc73
Merged #282-#288: perf-chain + timing retries, /sc-security small-scope pass, cc-audit delta
(6 Bash gaps, webhook/Telegram secrets, browser stores on Read). aidevops delta opened #289/#290,
CI running at hand-off. 4.4.6 held. This hand-off: docs PR #291.
Detail: `.claude/handoff-104cfc73-8853-40b7-9d59-e1f2d891a351.md`

#### 2026-11-10 — 104cfc73
Merged #274-#281: ReDoS, .claude dir, cluster identity flags + tfstate, prompt/env allowlists,
README, direnv + token formats (phantom-secrets delta). Handback replay: 3 of 5 refusals were FPs.
Then #281: commit-prose separator FP, one subagent notice, signed-URL patterns. 4.4.6 held.
Detail: `.claude/handoff-104cfc73-8853-40b7-9d59-e1f2d891a351.md`

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
