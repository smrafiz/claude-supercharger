# Handoff — claude-supercharger

The project's carry file: **one per project, tracked in git, read first by a fresh
session on any machine.**

### Current State
*Verified 2026-11-14, session `e7f6ce82`.*

- **Released: v4.4.6** (2026-11-13), tag on `88699aa6`. **Master `7ef44edf`** carries two
  unreleased PRs: #302 (Bidi/Trojan Source warn) and #303 (JWT / torch.load / CORS warns).
- Master CI + Host contract green on `62e8e3c3` (#302). #303's dispatched run (incl.
  Windows) green on attempt 2; its master push run not checked.
- **Open PRs:** none. **In flight:** none.
- **Audits closed:** cc-audit, aidevops (2 rounds), lodeline, kintsugi-harness.
  Parked by the user: `x=rm; $x -rf /`.
- **Open questions:** `disableAllHooks: true` vs user hooks (2026-11-12 brief); widen the
  6s timeout in `tests/test-update-check.sh:69` (Windows flake, 2026-11-14).
- Per-machine (this machine, 2026-11-14): 0 stashes; stale local `rel/4.4.5`.
- **Releasing:** `release.sh stage X.Y.Z --message ... --yes`, wait for rel CI, then
  `release.sh promote X.Y.Z --yes` (Windows is checked on master's base commit).
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

#### 2026-11-14 — e7f6ce82
Reviewed kintsugi-harness; probed 24 scenarios against our hooks. Merged #302 (Bidi /
Trojan Source warn) and #303 (JWT verify off, bare torch.load, any-origin CORS + creds).
#303 CI: py-floor `:=` grep FP fixed; Windows update-check 6s timeout flaked once.
Detail: `.claude/handoff-e7f6ce82-f0ce-4e41-957d-c06160b73ecb.md`

#### 2026-11-13 (deep) — 00ecfc20
Merged #299; master went red on the ubuntu-26.04 image switch. Root cause: timing EXIT trap
rewrote a deny (exit 2) to exit 1 on an unwritable audit dir — fixed in #301. Released v4.4.6.
Detail: `.claude/handoff-00ecfc20-17c7-4686-8d8f-3c1c1b36af96.md`

#### 2026-11-12 (deep) — 104cfc73
Merged #292-#297: desktop-input category, aidevops round 2 (Google secrets, OAST catchers, 13
injection families, harness-message secret warn), lodeline config-scan keys. Merged #298 (MCP,
frontmatter hooks, AGENTS.md). Open: #299 (normalizer bypasses), CI running. 4.4.6 held.
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
