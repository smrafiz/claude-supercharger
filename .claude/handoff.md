# Handoff — claude-supercharger

The project's carry file: **one per project, tracked in git, read first by a fresh
session on any machine.**

### Current State
*Verified 2026-11-02, session `3d213381`.*

- **Released: v4.4.2** (2026-11-01). Machine A runs 4.4.2 (updated 2026-11-02). Release only on the
  user's word; commit the carry file BEFORE `release.sh stage`.
- **master `28dab38e`**, unreleased since 4.4.2: #217 gh api search query as data, #218 README vote
  counts removed, #219 scripted demo refresh, #220 compactor excerpt starts at the failure detail.
- **Open PRs:** #221 README top image = real Claude Code session (worktree `demo2`); #222 session
  memory no longer leaks across projects (worktree `ckpt`). Suites were pending; merge pinned on green.
- **Next (agreed order):** issue 2 plain-language block reasons in safety.sh (keep the raw
  `dangerous pattern:` text in the block log, learn-from-blocks parses it); issue 4 economy hooks
  `TIER=$(grep …)` `|| true`; then statusline token source on plugin installs, `resets_at` stability,
  compactor rewrite order. Then 4.4.3 on the user's word.
- **Windows jobs:** 4 shards + gate `Windows (Git Bash)`; PR CI skips Windows, dispatch for guard changes.
- **Merging:** `gh pr merge --match-head-commit <full sha>`, always pinned.
- **Open decision (user):** roadmap item 5 (recursive delete outside project / of home: ask?);
  5 unmerged local branches to keep or delete.
- **Open (user):** star-keeper commitTypes; Machine B commit-msg hook; radius-apps guard-push wrapper,
  rotate CRON_SECRET, re-enable Actions.

### Per-machine / per-account facts
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

#### 2026-10-30 — d1f49e55
Merged #202 (Windows dispatched, green). Added `/sc-de-ai` (from petergyang/no-ai-slop, MIT) wired into
the writer agent, and the Issues List reply rule (from trycompai/crm). Audited video-use (nothing) and
re-checked SkillSpector; its MCP-config gap fixed in #203 (merged) and the Bash-read side in PR #204.
Detail: `.claude/handoff-d1f49e55-4f46-4a63-81cd-501bede3fbfd.md`

#### 2026-10-28 (deep) — 3d213381
Taking all of randommonicle/claude-skills into 4.4. Merged #184-#196; #197 SQL gaps waiting on Windows;
secret-printing + PowerShell secrets built, uncommitted. A replay caught two errexit fail-opens the new
tests missed (memory `errexit-in-guard-is-fail-open`).
Detail: `.claude/handoff-3d213381-9717-4755-b743-9b2b101ebce9.md`
