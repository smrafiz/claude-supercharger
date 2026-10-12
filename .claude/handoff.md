# Handoff — claude-supercharger

The project's carry file: **one per project, tracked in git, read first by a fresh
session on any machine.**

### Current State
*Verified 2026-10-12, session `3d213381`.*

- **Released: v4.3.4** (2026-10-12; installed on Machine A, `command-context.py` runs).
  4.3.3 = `/sc-mcp-audit` (#114) + release gate skip (#112); 4.3.4 = live context in
  `/sc-status`, `/sc-why`, `/sc-perf` via `!` injection + notifier build explains a broken
  Swift toolchain (#115). master = `a0ee078`, no open PRs, nothing mid-flight.
- **Unverified:** the three `!` commands inside a fresh interactive session (headless measured).
- **Next (backlog):** 4.4.0 remove old command redirect stubs (needs a cleanup step).
- **Watch:** colleagues' 4.3.2 cost reset; notification layout feedback.
- **Release recipe:** stage right after master CI is green (gate skipped), one detached
  finish job (stage → rel CI → promote → update) + ONE completion notice; user said "do not
  monitor". Windows fix? probe with a TEST_GLOB-narrowed workflow_dispatch first.
- **Machine A:** 4 stashes (`aborted-stage-4.3.0-bump`, `osc-notify-default-4.3.0`, `sog`,
  release.sh copy of #54) + 8 extra worktrees; drop only on user's say-so.
- **Machine B:** unknown. **Open (user):** radius-apps guard-push wrapper; rotate CRON_SECRET.

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

#### 2026-10-12 — 3d213381
4.3.3 (/sc-mcp-audit, gate skip) and 4.3.4 (live `!` context in sc-status/why/perf, Swift
toolchain hint) released; each via one detached finish job, gate skipped on green master.
Detail: `.claude/handoff-3d213381-9717-4755-b743-9b2b101ebce9.md` (2026-10-11 deep)

#### 2026-10-11 (deep) — 3d213381
4.3.1 + 4.3.2 released; #112 release gate skip merged. Found/fixed $11.7M lifetime cost
over-count (two writers dropping the offset map). /sc-mcp-audit WIP on its branch.
Detail: `.claude/handoff-3d213381-9717-4755-b743-9b2b101ebce9.md` (2026-10-11 deep)

#### 2026-10-11 — 3d213381
v4.3.1 released after 2 master-Windows reds (symlink test on Git Bash; python shebang
stamp) and 2 load-flaked stage gates. Added install speed-up, notification redesign,
quiet-when-focused. Found the inflated lifetime cost file.

#### 2026-10-08 (deep) — 3d213381
#106 + #107 merged (quote-split join, symlinked dotenv, notifier icon/spinner, 2.1.292 floor);
4.3.1 staging. Notifier lessons → memory macos-notification-facts, consent rule.
Detail: `.claude/handoff-3d213381-9717-4755-b743-9b2b101ebce9.md` (2026-10-08 deep)

#### 2026-10-08 — 3d213381
4.2.1 + 4.3.0 shipped: notification never fired (Stop payload has no cost field), commands
renamed sc- with hash-checked migration, frontmatter/user-only commands, opt-in macOS
notifier app (consent fix after user flagged silent install). No per-session brief written.
