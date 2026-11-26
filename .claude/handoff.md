# Handoff — claude-supercharger

The project's carry file: **one per project, tracked in git, read first by a fresh
session on any machine.**

### Current State
*Verified 2026-11-27, session `5623ea04` ("Supercharger"); machine `/Users/srafiz` (per-machine).*

- **Released: v4.4.9** (latest tag). Master `d1bc4692` (= #376 covers-file writer on top of #375). Master's own post-merge CI NOT read; #376's branch CI was green on Windows, macOS, Ubuntu (run 45866576025). Unreleased and on hold (user): #366, #368, #370-#376. No open PRs.
- **Open work with steps:** `docs/PENDING-2026-11-26.md` (covers-file item 2.3 is DONE by #376; the rest stands). Next: user's live probe; `stop-verify` trust gate (needs the user's 3 decisions); batch-editor PR; input-size fail-open; claim-gate readback arm.
- **Not yet done:** tell the `Readback` peer that #376 merged and about the CRLF fix `c3edd713` (it was told the PR number only). It keeps its settings-grep fallback until release.
- **Found this session:** Windows python wrote `.disabled-hooks` as CRLF, so per-project `disableHooks` never matched all but the last entry, for every hook. Fixed in `_load_disabled_hooks`. Detail in the per-session brief.
- **Local branches (per-machine, staleness unchecked):** `docs/2026-11-17-brief`, `feat/approval-codes`, `feat/disk-watch`, `feat/office-read`, `fix/memokit-delta`, `fix/quoted-pipe-fp`.
- Rules from earlier briefs (Sonnet builds / Opus reviews, no worktrees, merge on the user's word) were not re-verified this session.

### Log
#### 2026-11-27 (deep) — 5623ea04
Built, tested and merged the readback covers-file writer (#376) and the CRLF `.disabled-hooks` fix it exposed on Windows CI. Full suite 9093/0. Merged #375 and #376 on the user's word. Memory: added the eighth Windows trap.
Detail: `.claude/handoff-5623ea04-b8ad-4148-977a-0f0a1aac8ffc.md`

#### 2026-11-26 (deep) — c7ed25f1
Merged #368-#374 after Opus loops (claim-gate false advisories, scanner screenshots fix, readback failure-tracker with a new sync PostToolUseFailure registration, pycache ignore, pending-items doc); deleted 7 merged branches. Planned (not built): stop-verify trust gate, covers file, claim-gate readback arm. Probe for the user not yet run.
Detail: `.claude/handoff-c7ed25f1-03ea-465a-820d-7e75d4eaf0d9.md`

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
