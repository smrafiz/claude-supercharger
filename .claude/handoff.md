# Handoff — claude-supercharger

The project's carry file: **one per project, tracked in git, read first by a fresh
session on any machine.**

### Current State
*Verified 2026-11-03, session `111c7837`.*

- **Released: v4.4.2.** **4.4.3 is ON HOLD by the user** — release only on their word; commit the
  carry file BEFORE `release.sh stage`.
- **master `b4fe7193`**, unreleased: #217-#229, #231, #227 (spend-guard), test-stdin-timeout fix.
- **Open PRs, all PR-CI green:** #230 citation-gate (`bb1c54b4`, Windows run 41501558568 queued),
  #232 /sc-handoff worktrees (`c5153b3a`, Windows green), #233 pipe-shell FP (`17b8fa31`, Windows
  green). Merge order #230 -> #232 -> #233, pinned. A background merge chain (session 111c7837)
  waits on 41501558568; check `gh pr list` before acting.
- **Not a flake:** test-stdin-timeout D failed twice on #230 (1s read timeout on Windows); fixed on
  master `b4fe7193` (A and D get 10s). Why only #230 tripped it is unexplained.
- **Next:** issue 2 plain-language block reasons; data-vs-command FP (quoted printf arg denied);
  KNOWN-ISSUES #8 (manifest generator drops hashes on a fresh clone).
- **Windows:** PR CI skips it; dispatch `gh workflow run ci.yml --ref <branch>` BEFORE merge.
- **Merging:** `gh pr merge N --squash --delete-branch --match-head-commit <full sha>`. In auto mode a
  force-push is denied: merge master into a PR branch, don't rebase it.
- **Open (user):** roadmap item 5 (recursive delete outside project: ask?); star-keeper commitTypes;
  Machine B commit-msg hook; radius-apps guard-push wrapper, rotate CRON_SECRET, re-enable Actions.

### Per-machine / per-account facts
- **Worktrees are per-machine.** `.claude/worktrees/` is not in git. On 2026-11-03 this machine had
  none of the four the previous brief listed; recreate from `origin/<branch>`. This machine now has
  `cite` (branch `cite-ff`) and `hwt`, plus stash `cite-count-fix` (safe to drop, already pushed).
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

#### 2026-11-03 (deep) — 111c7837
Merged #227 (Windows failure was the test: MSYS cwd in JSON). Fixed #232 manifest (+1 hash; generator
would have dropped 26 — KNOWN-ISSUES #8) and #230 install count 175. #230 Windows hit a suspected
failure in test-stdin-timeout D, twice: not a flake, a 1s read timeout. Fixed on master `b4fe7193`,
merged into #230 (`bb1c54b4`), Windows 41501558568 + merge chain left running.
Detail: `.claude/handoff-111c7837-ccb3-4199-a4d8-57243e3a9fdd.md`

#### 2026-11-02 (deep, end of day) — 3d213381
Merged #221-#226, #228, #229, #231 (memory leak + Windows fix, MCP lineup, real demo GIF, profiles,
economy, pwn issue_comment, suppression ask). Open: #227 spend-guard, #230 citation-gate, #232, #233.
4.4.3 held by the user.
Detail: `.claude/handoff-3d213381-9717-4755-b743-9b2b101ebce9.md`

#### 2026-11-02 (deep) — 3d213381
Updated Machine A to 4.4.2. Merged #217-#220. README top image is now a real Claude Code session
(#221, open); found and fixed a cross-project session-memory leak (#222, open). Issue 3 (UPDATE) is
intended. Next: plain-language block reasons, economy hooks.
Detail: `.claude/handoff-3d213381-9717-4755-b743-9b2b101ebce9.md`

#### 2026-11-02 (deep) — e51274e4
Merged #216, released v4.4.2. Fixed release.sh `--yes`, blast push count, CI badge (per-commit master
concurrency). README Highlights + problems table. Gaps re-checked: all fixed upstream; no compound
auto-approve. PR #217 (gh api search query as data) awaiting CI.
Detail: `.claude/handoff-e51274e4-04a0-4dad-935e-5066df4f92a2.md`

#### 2026-10-31 — d1f49e55
Merged #204-#207 (MCP-config Bash read, workaround check from trackline, benchmark gaps 1-3, 200K
compact nudge + model aliases from Provost). Roadmap written. Windows atomic-deploy flake diagnosed as a
non-atomic replace (file briefly missing, never torn). 4.4.0 ready to stage.
Detail: `.claude/handoff-d1f49e55-4f46-4a63-81cd-501bede3fbfd.md`
