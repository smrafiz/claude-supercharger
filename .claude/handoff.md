# Handoff — claude-supercharger

The project's carry file: **one per project, tracked in git, read first by a fresh
session on any machine.**

### Current State
*Verified 2026-11-01, session `e51274e4`.*

- **Released: v4.4.2** (`fcdd5535`, 2026-11-01). Ships #213-#216.
- **master `cb27cc7f`**, 3 commits past v4.4.2: `4ed9d209` release.sh `--yes` fix, `fb0f76a3` blast
  push-count fix, `cb27cc7f` README highlights + problems table. CI green on `fb0f76a` (all jobs).
- **No open PRs.** Local branches: master, rel/4.2.0. One old stash (feat/block-workaround-warn).
- **Windows jobs:** 4 shards + `Windows (Git Bash)` gate. PR CI skips Windows; dispatch
  `gh workflow run ci.yml --ref <branch>` for guard changes. rel/* pushes skip Windows too; promote
  accepts Windows green on master at the base commit.
- **Merging:** `gh pr merge --match-head-commit <full sha>`, always pinned.
- **CI badge** turns red after back-to-back master pushes (cancelled runs read as failing). Open (user):
  A stop cancelling on master, or B leave it.
- **Next planned:** compound-command auto-approve (#28240/#16561) — plan first, safety rule.
- **Open decision (user):** roadmap item 5, recursive delete outside project / of home: ask?
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

#### 2026-11-01 — e51274e4
Merged #216 (Windows dispatched, green); released v4.4.2. Fixed release.sh `--yes` silent exit and the
blast push count for commit-then-push. README gained Highlights + an issue-linked problems table.
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

#### 2026-10-26 (deep) — 3d213381
Audit day: ECC re-audit, Karpathy, Ponytail, cc-switch, gstack + open-source prompts, Graphify,
Caveman, Orca, claude-mem, archify, ruflo, SkillSpector, raptor. Shipped #173-#179 to master, opened
#180-#182; found rules/*.yml never loads, CC cost already includes subagents, Caveman rewrites commands.
Later: merged #180-#183; #184 (Windows has no POSIX modes), #185 allowlists (its build agent routed
around a refusal), #186 README-count test.
Detail: `.claude/handoff-3d213381-9717-4755-b743-9b2b101ebce9.md`
