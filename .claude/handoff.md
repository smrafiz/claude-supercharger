# Handoff — claude-supercharger

The project's carry file: **one per project, tracked in git, read first by a fresh
session on any machine.**

### Current State
*Verified 2026-11-24, session `c7ed25f1`.*

- **Released: v4.4.9** (tag + GitHub release 2026-11-24 05:15Z; the old "unreleased" line was wrong).
- **Master `1476f7e2`** = #366 (boxdawn replay gaps + 5 FPs) on top of the release. NOT released: installed
  copies lack it until the next release + `/sc-update`. No open PRs. Master CI for it was running, result unseen.
- **Open:** is `"rm" -rf /` / plain `rm -rf /` allowed on Git Bash on master? Unverified; probe via Windows dispatch.
- **Never use Fable** (user). **No worktrees; no Artifacts** (user). **Never `git checkout` during a background suite.**
- **Merging:** wait until `gh pr checks N` shows NOTHING pending (I merged #366 with Version consistency pending);
  Windows via `gh workflow run ci.yml --ref <b>` first (PR CI skips it). Guard changes: Opus review before the PR.
- **Releasing:** `release.sh stage X.Y.Z --message ... --yes`, wait for rel CI, `release.sh promote X.Y.Z --yes`; only on the user's word.
- **Per-machine (work Mac):** installed version not re-checked this session; 6 old stashes, never pop.

### Log
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

#### 2026-11-19 (deep) — eaedd321
Merged #335–#339 and #342 (symlink targets, managed MCP allowlist, claim-gate reviewer, compress
negations, credential-read gaps A, review-prompt rules). Audits: avhn/secret, agent-white-hat (replays),
vantage, Agasthy and four more. B/C open; plan in docs/GUARD-GAP-PLAN-2026-11-19.md.
Detail: `.claude/handoff-eaedd321-5e4c-41af-80ed-a51a6c772596.md`

#### 2026-11-18 — eaedd321
Reviewers found fail-opens in #325/#326/#329; fixed, then merged #324–#333 and released v4.4.8.
New: #331 `>|` in 4 guards, #332 disk-watch `$(( ))` code exec, #333 safety.sh fail-closed + `--build-arg`.
Detail: `.claude/handoff-eaedd321-5e4c-41af-80ed-a51a6c772596.md`
