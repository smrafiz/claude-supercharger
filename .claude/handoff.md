# Handoff — claude-supercharger

The project's carry file: **one per project, tracked in git, read first by a fresh
session on any machine.**

### Current State
*Verified 2026-10-08, session `3d213381`.*

- **Released: v4.3.0.** #107 (4.3.1 content) merged to master as `cecb1fd`; **4.3.1 stage
  running** (detached). Remaining: rel/4.3.1 CI + master Windows → promote → update.sh.
- **Open PRs:** this carry-file update (`docs/2026-10-08-handoff`).
- **Next:** MCP tool-description poisoning — can hooks see descriptions? Then `!` live
  context in sc-status/perf/why (test the not-allowlisted behaviour first).
- **Watch:** 4.3.0 command migration on colleagues' machines; 4.2.0 asks for FPs.
- **Release recipe:** stage detached (`nohup … & disown`), promote `--yes`, update.sh `--yes`.
  A failed stage leaves a local `rel/X.Y.Z` AND uncommitted bump edits.
- **Machine A:** installed 4.3.0 (4.3.1 pending). Notifier app installed, its notification
  permission OFF (re-enable in System Settings). Stashes `osc-notify-default-4.3.0`,
  `aborted-stage-4.3.0-bump`, `sog` safe to drop. Worktree `b4` (merged branch) removable.
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

#### 2026-10-08 (deep) — 3d213381
#106 + #107 merged (quote-split join, symlinked dotenv, notifier icon/spinner, 2.1.292 floor);
4.3.1 staging. Notifier lessons → memory macos-notification-facts, consent rule.
Detail: `.claude/handoff-3d213381-9717-4755-b743-9b2b101ebce9.md` (2026-10-08 deep)

#### 2026-10-08 — 3d213381
4.2.1 + 4.3.0 shipped: notification never fired (Stop payload has no cost field), commands
renamed sc- with hash-checked migration, frontmatter/user-only commands, opt-in macOS
notifier app (consent fix after user flagged silent install). No per-session brief written.

#### 2026-10-06 — 3d213381
#99 fixed master Windows (CR-CR-LF). Sweep 5 (4 research agents) -> PR #100: normalizer
bypasses, FPs, Mods/Artifact/token/remote coverage. Classifier cut many patch turns.
Detail: `.claude/handoff-3d213381-9717-4755-b743-9b2b101ebce9.md` (2026-10-06 deep)

#### 2026-10-05 (evening) — 3d213381
Batch 4 merged (#98, 50405e3) after fixing 3 tests (2 test bugs, 1 real crontab separator gap
present since v4.1.17); suite 6212/0. v4.2.0 staging/promoting detached.
Detail: `.claude/handoff-3d213381-9717-4755-b743-9b2b101ebce9.md` (Status — evening)

#### 2026-10-05 — 3d213381
v4.1.30 out (#93 #94 #96). Four research rounds -> #97 (v4.2.0 features) merged; batch 4
(FP audit fixes, CI/GitHub, infra coverage, docs) on feat/batch4, 3 tests to fix, then ship 4.2.0.
Detail: `.claude/handoff-3d213381-9717-4755-b743-9b2b101ebce9.md`

