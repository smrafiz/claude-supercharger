# Handoff — claude-supercharger

The project's carry file: **one per project, tracked in git, read first by a fresh
session on any machine.**

### Current State
*Verified 2026-11-12, session `104cfc73`.*

- **Released: v4.4.5** (2026-11-08), tag on `bda06a90`. This machine (per-machine) runs commit `954fafb` (label 4.4.5).
- **Master `fc994dde`**: #289-#297 merged 2026-11-11/12, each 12/12 CI green.
- **Open, not merged:** #298 (MCP launchers, frontmatter hooks, AGENTS.md; rebased `38b3cd23`,
  suite 7971/0, CI 43205727007) and #299 (normalizer bypasses, `2b9ab907`, CI 43207779757).
  Merge #298 then #299 when 12/12 green.
- **4.4.6 HELD** (user): #264-#299. Release only on their word.
- **Audits closed:** cc-audit, aidevops (2 rounds), lodeline. Parked by the user: `x=rm; $x -rf /`.
- **Open question:** does a project `disableAllHooks: true` disable user hooks? Docs say yes; live
  test blocked by our self-mod guard; see the brief for the manual test.
- Per-machine: 6 stashes (incl. `3d45886a`) are the user's; branch `feat/supply-chain-gaps`.
- **Releasing:** `release.sh stage X.Y.Z --message ... --yes` (background); promote needs Windows green.
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

#### 2026-11-12 (deep) — 104cfc73
Merged #292-#297: desktop-input category, aidevops round 2 (Google secrets, OAST catchers, 13
injection families, harness-message secret warn), lodeline config-scan keys. Open: #298 (MCP,
frontmatter hooks, AGENTS.md) and #299 (normalizer bypasses), CI running. 4.4.6 held.
Detail: `.claude/handoff-104cfc73-8853-40b7-9d59-e1f2d891a351.md`

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
