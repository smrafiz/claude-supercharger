# Handoff — claude-supercharger

The project's carry file: **one per project, tracked in git, read first by a fresh
session on any machine.**

### Current State
*Verified 2026-11-01, session `3d213381`.*

- **Released: v4.4.0** (2026-11-01 03:43 UTC, installed on Machine A). **4.4.1 merged, not released**;
  release only on the user's word (`tools/release.sh stage patch` → `promote 4.4.1`).
- **master `eeca2f73`.** Since 4.4.0: #208 README fixes, #209 statusline Weekly shows without a
  5-hour window (this account no longer has one), #210 `/sc-update` installs newer code on the same
  release for non-git installs, #211 Windows suite on 4 machines (~40 min instead of ~100), #212
  rate-limit-advisor warns on the weekly limit at 90%/95%. Master CI on `eeca2f73` started at writing.
- **No open PRs, no PR worktrees.** 5 unmerged local branches kept (closed PRs / debug): user to decide.
- **Windows jobs:** `Windows (Git Bash) shard N/4` run the suite; `Windows (Git Bash)` is the gate and
  reads all four logs. `tests/run.sh TEST_SHARD=i/n` (dropped from the env after reading).
- **Windows replace is not atomic:** ~1 read in 1.4-2.5k finds a hook missing during redeploy (never
  torn). Test now reports it on Windows instead of failing. Roadmap item 1, after 4.4.0.
- **Windows rule:** PR CI skips Windows; dispatch `gh workflow run ci.yml --ref <branch>` for guard
  changes. Branches cut before `a98a5f29` can still flake on atomic-deploy: `gh pr update-branch`.
- **Merging:** `gh pr merge --match-head-commit <full sha>` was allowed from Claude on 2026-11-01
  (#208-#212); it had been denied earlier. Always pin the head SHA.
- **Open decision (user):** roadmap item 5, should recursive delete of an absolute path outside the
  project, or of home, ask?
- **Open (user):** star-keeper commitTypes config; Machine B commit-msg hook; radius-apps guard-push
  wrapper, rotate CRON_SECRET, re-enable Actions.

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

#### 2026-10-25 (deep) — 3d213381
4.3.25 released. #170 (installer missed receipts.py/notifier) then broke reinstall on master (dir swap);
#171 fixed it. 4.3.26 job in flight. Three tests that could not fail, fixed.
Detail: `.claude/handoff-3d213381-9717-4755-b743-9b2b101ebce9.md` (2026-10-25 deep)
