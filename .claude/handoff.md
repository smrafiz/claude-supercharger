# Handoff — claude-supercharger

The project's carry file: **one per project, tracked in git, read first by a fresh
session on any machine.**

### Current State
*Verified 2026-11-07, session `1c2a497d`.*

- **Released: v4.4.4** (2026-11-06), tag `65bd9927`. This machine (per-machine) runs 4.4.4.
- **Master `b1e4bc58`, CI green, 15 commits unreleased:** #250-#254 (see log), #255+#256
  (`tests/host-contract/`: real `claude` binary vs a local stand-in model, 19 cases, weekly
  stable/latest cron), #257 (handback gate: bare `stub`/`placeholder` no longer refuse; replay of
  82 real handbacks 5 → 2 refused, both true). **4.4.5 on hold** (user).
- **Open PRs:** none.
- **Next (recommended):** PreToolUse advisory for `test|build|lint ... | tail/head/grep` without
  `pipefail` (exit code masked; idea from yotamleo-org/Himmel `block-tail-pipe-on-gates`), then 4.4.5.
- **Releasing:** `release.sh stage X.Y.Z --message ... --yes`; push CI skips Windows, so dispatch
  `gh workflow run ci.yml --ref rel/X.Y.Z`; user runs `promote X.Y.Z --yes` (`!` has no stdin).
- **Merging:** `gh pr merge N --squash --delete-branch --match-head-commit <full sha>`.
- **Open:** replay handbacks after a week of subagent use on 4.4.4+; risk-review log ~2026-11-20;
  SpecLock (parked); `/sc-security` never run on a real repo; economy re-measure; per-guard
  false-alarm study (backlog). SubagentHandback is not offered offline, so CI cannot hold it.

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

#### 2026-11-05 → 11-07 (deep) — 1c2a497d
Released v4.4.4 (#239-#249). Merged #250-#257: 6h update check, commit-check `-F`, batch-editor,
report-only risk review, host-contract suite (#255/#256, from mnema), handback gate FP fix (#257).
Reviewed mnema, systemone-judge, Himmel: took host contract; pipe-exit advisory next. 4.4.5 held.
Detail: `.claude/handoff-1c2a497d-cf2e-47c6-b04d-a1f84d704781.md`

#### 2026-11-04 (deep) — 3d213381
Merged #241-#244 (cloud-cli asks, claim gate stale/zero-test, supply-chain asks, paste overrun,
tamper chmod). Found Stop/SubagentStop notes reach nobody; subagents need a PreToolUse deny on
SubagentHandback. #245 does that and retires subagent-stop-check (merged 2026-11-05).
Detail: `.claude/handoff-3d213381-9717-4755-b743-9b2b101ebce9.md`

#### 2026-11-04 (deep) — e323355d
Released v4.4.3 (promote run by the user; auto mode denies it). release.sh: gate prints failing
checks, promote reports a failed pull. PR #239: Cloudflare security-audit-skill ported into
/sc-security (domain files, needs_validation, coverage ledger, DoS deep-only), awaiting CI.
Detail: `.claude/handoff-e323355d-8bb7-445a-9d69-1c893ff551cb.md`

#### 2026-11-03 — 3d213381
Merged #230, #232-#238: autopilot `full`, plain block reasons, grep -e FP, manifest generator,
lock-aware sed -i / perl -pi. Releasing 4.4.3 on the user's word.
Detail: `.claude/handoff-3d213381-9717-4755-b743-9b2b101ebce9.md`

#### 2026-11-03 (deep) — 111c7837
Merged #227 (Windows failure was the test: MSYS cwd in JSON). Fixed #232 manifest (+1 hash; generator
would have dropped 26 — KNOWN-ISSUES #8) and #230 install count 175. #230 Windows hit a suspected
failure in test-stdin-timeout D, twice: not a flake, a 1s read timeout. Fixed on master `b4fe7193`,
merged into #230 (`bb1c54b4`), Windows 41501558568 + merge chain left running.
Detail: `.claude/handoff-111c7837-ccb3-4199-a4d8-57243e3a9fdd.md`
