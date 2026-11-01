# Handoff — claude-supercharger

The project's carry file: **one per project, tracked in git, read first by a fresh
session on any machine.**

### Current State
*Verified 2026-11-02, session `e51274e4`.*

- **Released: v4.4.2** (`fcdd5535`, 2026-11-01). Ships #213-#216.
- **master `d821aff8`+**, past v4.4.2: `4ed9d209` release.sh `--yes`, `fb0f76a3` blast push count,
  `cb27cc7f` README highlights/problems table, `d821aff8` CI per-commit concurrency on master, plus docs.
- **Open PR #217** (`fix/gh-api-search-query`): gh api search query treated as data. Dispatched full CI
  41336436428 running at writing; merge pinned to head on green.
- **CI badge:** fixed going forward (`d821aff8`); red until a post-fix master run finishes green.
- **No compound auto-approve** — upstream covers it; see `docs/COMMUNITY-WANTS-2026-09-17.md` § Update 2026-11-01.
- **Windows jobs:** 4 shards + gate. PR and rel/* pushes skip Windows; dispatch
  `gh workflow run ci.yml --ref <branch>` for guard changes. Promote accepts Windows green on master base.
- **Merging:** `gh pr merge --match-head-commit <full sha>`, always pinned.
- **Next (user):** cut 4.4.3 after #217? Distribution: replies on top complaint threads are public posts.
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

#### 2026-10-26 (deep) — 3d213381
Audit day: ECC re-audit, Karpathy, Ponytail, cc-switch, gstack + open-source prompts, Graphify,
Caveman, Orca, claude-mem, archify, ruflo, SkillSpector, raptor. Shipped #173-#179 to master, opened
#180-#182; found rules/*.yml never loads, CC cost already includes subagents, Caveman rewrites commands.
Later: merged #180-#183; #184 (Windows has no POSIX modes), #185 allowlists (its build agent routed
around a refusal), #186 README-count test.
Detail: `.claude/handoff-3d213381-9717-4755-b743-9b2b101ebce9.md`
