# Handoff — claude-supercharger

The project's carry file: **one per project, tracked in git, read first by a fresh
session on any machine.**

### Current State
*Verified 2026-11-07, session `1c2a497d` (resumed as `92edb542`).*

- **Released: v4.4.4** (2026-11-06), tag `65bd9927`. This machine (per-machine) runs 4.4.4;
  Concise output style confirmed applied mid-session.
- **Master `2beee9fb`, CI green, unreleased:** #250 (update check every 6h, same-session
  statusline flag), #251+#252 (commit-check reads `-F`/`--file`/`-F ~/x`/`-m "$(cat f)"`),
  #253 (batch-editor agent, Haiku), #254 (risk-review report-only log in claim gate →
  `audit/risk-review.jsonl`; plan `docs/RISK-REVIEW-PLAN.md`). **4.4.5 on hold** (user).
- **Open PRs:** none. CI reds today were macOS runner capacity (0-step cancels) and one
  `test-bounded-run` Windows flake (timeout took 21s; passed on rerun).
- **Releasing:** `release.sh stage X.Y.Z --message ... --yes`; push CI skips Windows, so dispatch
  `gh workflow run ci.yml --ref rel/X.Y.Z`; user runs `promote X.Y.Z --yes` (`!` has no stdin).
- **Merging:** `gh pr merge N --squash --delete-branch --match-head-commit <full sha>`.
- **Open:** risk-review: read the log ~2026-11-20, then decide blocking; SpecLock (parked); `/sc-security` never run on a real repo; economy
  re-measure once Concise sessions exist; user's: rotate the Context7 key, star-keeper,
  Machine B commit-msg hook, radius-apps.

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

#### 2026-11-07 (deep) — 1c2a497d
Deep brief for the 2026-11-05→07 session (v4.4.4, #249-#254). HOOK_AUTHORING notes 2026-11-06;
memory: zsh tool shell, agents picked by description, Windows whole-run rerun, dispatch capacity.
Detail: `.claude/handoff-1c2a497d-cf2e-47c6-b04d-a1f84d704781.md`

#### 2026-11-06 (late) — 1c2a497d
Merged #252-#254: `-F ~/path`, batch-editor agent (from Provost), risk-review report-only arm.
Reviewed norton77930/Provost: took mech-executor + risk-triggered review; skipped the rest.
Detail: `.claude/handoff-1c2a497d-cf2e-47c6-b04d-a1f84d704781.md`

#### 2026-11-06 (later) — 1c2a497d
Merged #250 (update-check lag) and #251 (commit-check `-F` gap, the `agent-handoff-gate:` cause).
Opened #252 (`-F ~/path`). 4.4.5 held by the user.
Detail: `.claude/handoff-1c2a497d-cf2e-47c6-b04d-a1f84d704781.md`

#### 2026-11-06 — 1c2a497d
Merged #249 (minimal tier sets Concise output style; Windows symlink test skips like
test-env-file-guard). Released v4.4.4 (#239-#249); user ran promote.
Detail: `.claude/handoff-1c2a497d-cf2e-47c6-b04d-a1f84d704781.md`

#### 2026-11-05 — 1c2a497d
Status check: #246-#248 merged, master green, no PRs. Carry file refreshed; 4.4.4 release
message drafted for #239-#248, awaiting the user's stage/promote run.
Detail: `.claude/handoff-1c2a497d-cf2e-47c6-b04d-a1f84d704781.md`
