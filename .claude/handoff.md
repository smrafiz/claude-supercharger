# Handoff — claude-supercharger

The project's carry file: **one per project, tracked in git, read first by a fresh
session on any machine.**

### Current State
*Verified 2026-11-20, session `e23c930b`.*

- **Released: v4.4.8.** 4.4.9 is **held by the user**; master has everything through #351. Release
  only on the user's word.
- **Master `7a79c335`, CI green.** Open: #352 (gap 4, claimed approval / orders to the assistant;
  checks and Windows green at `8ad434c7`, waiting on the user's "merge"). No stash, no worktrees.
- **Merged this session:** #341, #344 (Read/WebFetch scanned), #345 (plugin disable denied), #346 (pip
  `-r/-c/-e`), #348 (download then chmod/run), #349 (`mshta`, `Unblock-File`), #350 (pip index-url,
  AGENTS.md base-URL scan, `report` verb), #351 (foreign settings allowing runners like `npx`, `find`).
- **Next work:** `docs/GUARD-GAP-PLAN-2026-11-19.md` Step 3 is done once #352 merges. Left: Step 4
  (install-gate design, ask before building), Step 5 (user decision on routed-around denies), and the
  separate-commands form of gap 1 (needs state across commands).
- **Unverified:** WebFetch's PostToolUse text is under `.result` (code handles both shapes; no live probe).
  The Bash-scanner pre-filter widened in #352 has no latency measurement.
- **Windows shard hang:** shard 2 of run 44716085537 hit the 90-minute timeout once with no output;
  the rerun passed. Treat a repeat as a real hang.
- **Merging:** `gh pr merge N --squash --delete-branch --match-head-commit <full sha>`; check the
  Windows dispatch AND master's post-merge CI. A macOS job cancelled with zero steps is capacity:
  `gh run rerun <id> --failed`.
- **Releasing:** `release.sh stage X.Y.Z --message ... --yes`, wait for rel CI, then
  `release.sh promote X.Y.Z --yes`.
- **No Artifacts** (user, 2026-11-19): plans go in `docs/*.md`. Per-machine: the work machine has 6 old
  stashes that are not this session's; never pop them.

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

#### 2026-11-20 — e23c930b
Merged #341, #344–#346, #348–#351; #352 open. Plan Step 3 gaps 1–7 done except the cross-command form
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

#### 2026-11-17 (deep) — c8c4db43
Merged #319–#323: skill-scan FP, LC_ALL=C normalize (≈40% faster), container bind-mount rm deny,
/sc-security chains, /sc-health allowManagedHooksOnly. Seven repo audits. 4.4.8 held by the user.
Detail: `.claude/handoff-c8c4db43-9e98-47e4-b1fc-0bcb9b1b8de6.md`

