# Handoff — claude-supercharger

The project's carry file: **one per project, tracked in git, read first by a fresh
session on any machine.**

### Current State
*Verified 2026-10-30, session `d1f49e55`.*

- **Released: v4.3.26** (2026-10-25). **Holding for 4.4.0** on the user's word: no 4.3.x releases;
  release only when the user says so (`tools/release.sh stage minor` → `promote 4.4.0`).
- **master `51792935`.** Merged since 4.3.26: #173-#202, then `/sc-de-ai` (`0e6e1e10`) and the
  Issues List rule (`51792935`) committed straight to master. **No open PRs.**
- **Master CI on `51792935`** (run 41042447466): in progress at writing. Windows has not yet COMPLETED
  on #202/sc-de-ai/Issues List — the earlier master runs were cancelled by newer pushes.
- **Open, small:** widen `lib_poison_patterns.py:65` MCP-config names per SkillSpector AS2
  (`mcp_settings.json`, `claude_desktop_config.json`, `.claude.json`); `cline_mcp_settings.json` is not in
  `env-file-guard.sh`. Unverified: a subagent invoking a slash command via `Skill` (writer → sc-de-ai).
- **Windows rule:** PR CI skips Windows; dispatch `gh workflow run ci.yml --ref <branch>` for anything
  touching cmd-normalize/safety/git-safety. Merge pinned with the FULL sha in `--match-head-commit`.
- **Merging is user-run:** the auto-mode classifier denies `gh pr merge` from Claude.
- **Open (user):** star-keeper commitTypes config; Machine B commit-msg hook (no co-author trailers);
  radius-apps guard-push wrapper, rotate CRON_SECRET, re-enable Actions.

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

#### 2026-10-30 — d1f49e55
Merged #202 (Windows dispatched, green). Added `/sc-de-ai` (from petergyang/no-ai-slop, MIT) wired into
the writer agent, and the Issues List reply rule (from trycompai/crm). Audited video-use (nothing) and
re-checked SkillSpector (one static-scan gap, not acted on).
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

#### 2026-10-21 (deep) — 3d213381
4.3.24 released after a reboot killed the first job. #168 Trust Receipts merged (Windows green after an
argv-conversion fixture fix). #169 audit-trail on shared secret patterns open; 4.3.25 releases both.
Detail: `.claude/handoff-3d213381-9717-4755-b743-9b2b101ebce9.md` (2026-10-21 deep)
