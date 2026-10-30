# Handoff — claude-supercharger

The project's carry file: **one per project, tracked in git, read first by a fresh
session on any machine.**

### Current State
*Verified 2026-10-28, session `3d213381`.*

- **Released: v4.3.26** (2026-10-25). **Holding for 4.4.0** on the user's word: no 4.3.x releases;
  release only when the user says so. Merged since 4.3.26: #173-#196 (master `2eb4a4d8`).
- **Master CI on `2eb4a4d8`:** green incl. Windows (run 40644488301). /sc-update installs master.
- **Open for 4.4:** merged #197 SQL gaps, #198 secret printing, #199 Windows backslash paths,
  #200 PostToolUse PowerShell parity (master `e2651166`; its first Windows run failed test-perf-chain
  once, rerun 308/308 clean), #201 weakened assertions (master `9641bb5c`, Windows 308/308).
  #202 DNS lookup built from a substitution asks on a detector overrun (pre-existing fail-open
  found under load; worktree `dnsover`). After #202: 4.4.0 release waits on the user.
  FP loosening DROPPED (user agreed): count reads (grep -c/-q, wc -l) already allow; names-only
  reads 0 real in 39,552 commands; output-to-file stays blocked.
- **Machine A coexists with Caveman** (API proxy + shrink-hook; telemetry/routing/cloud turned OFF
  2026-10-26), Ponytail 5.3.2 (band hidden), Graphify skill (plinth + radius-bundles graphs built).
  See memory `caveman-coexistence`: it elides FAIL/deny lines and rewrites Bash commands.
- **Windows rule:** PR CI skips Windows; dispatch `gh workflow run ci.yml --ref <branch>` for anything
  touching cmd-normalize/safety/git-safety.
- **Release recipe:** detached `launchctl submit` job, quote PATH, dies on reboot. Remove PR worktrees.
- **Open (user):** star-keeper commitTypes config; Machine B commit-msg hook (no co-author trailers);
  4 stashes on Machine A; radius-apps guard-push wrapper, rotate CRON_SECRET, re-enable Actions.

### Per-machine / per-account facts
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

#### 2026-10-20 (deep) — 3d213381
Merged #164/#163/#165/#166 for one 4.3.24 (32 guards fail closed, drift alarm, CVE-class fixes).
Master went red twice on Windows (MSYS path inside a string, then CRLF); fixed, branch Windows run
green. Release job in flight.
Detail: `.claude/handoff-3d213381-9717-4755-b743-9b2b101ebce9.md` (2026-10-20 deep)

