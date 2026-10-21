# Handoff — claude-supercharger

The project's carry file: **one per project, tracked in git, read first by a fresh
session on any machine.**

### Current State
*Verified 2026-10-20, session `3d213381`.*

- **Released: v4.3.23** (master). Installed v4.3.23 on Machine A.
- **In flight: 4.3.24**, one combined release. All four PRs merged: #164, #163, #165, #166
  (master `82b2146`). Release job (Machine A, launchd `sc.finish.4324`) waits on master CI for
  `82b2146`, then stage, rel CI, promote, update. Result: `~/.cache/sc-finish-4.3.24.result`.
- **Docs PR `docs/handoff-1020`** (Windows notes, this file): merge after the release.
- **Windows rule:** PR CI skips the Windows job. For Windows-touching work, run
  `gh workflow run ci.yml --ref <branch>` and gate the merge on it (4.3.24 went red on master twice).
- **Release recipe:** detached `launchctl submit` job that removes its own label on EXIT; does
  NOT survive a reboot. PR gate = run on head SHA + both `Test suite` checks by name.
  Remove each PR worktree once merged.
- **Next candidates:** Trust Receipts (narrow outward-action ledger).
- **Open (user):** star-keeper `git config supercharger.commitTypes "words notes access handoff drafts"`.

- **Machine A:** 4 stashes (drop only on the user's say-so); worktree `handoff-1020` only.
- **Machine B:** unknown. **Open (user):** radius-apps guard-push wrapper; rotate CRON_SECRET;
  re-enable radius-apps Actions.

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

#### 2026-10-20 (deep) — 3d213381
Merged #164/#163/#165/#166 for one 4.3.24 (32 guards fail closed, drift alarm, CVE-class fixes).
Master went red twice on Windows (MSYS path inside a string, then CRLF); fixed, branch Windows run
green. Release job in flight.
Detail: `.claude/handoff-3d213381-9717-4755-b743-9b2b101ebce9.md` (2026-10-20 deep)

#### 2026-10-19 (deep) — 3d213381
Released 4.3.21–4.3.23; 4.3.24 in flight. Replayed 4,000 real calls through every PreToolUse hook:
core guards never exit outside 0/2 (so `onFailure:block` is safe), and 8 guards were dead on the plugin
(committed 644). Per-repo commit types; health catches IS_DEMO.
Detail: `.claude/handoff-3d213381-9717-4755-b743-9b2b101ebce9.md` (2026-10-19 deep)

#### 2026-10-18 (deep) — 3d213381
Released 4.3.18–4.3.20; 4.3.21 and 4.3.22 (STE mode, handoff --html) followed on 10-19. Found and fixed two cost errors (per-line usage 2.04x,
family pricing 1.57x), an inert screen redactor, a `$IFS` evasion and a credential fail-open under load.
Detail: `.claude/handoff-3d213381-9717-4755-b743-9b2b101ebce9.md` (2026-10-18 deep)

#### 2026-10-17 (deep) — 3d213381
4.3.14–4.3.17 released after a gist-500 CI flake stalled the chain. Built #145–#147 (grep FP,
event-logger fields, guard canary + /sc-health); batched them into one 4.3.18. Closed 3 research items. 4.3.18 held: Windows CI caught the
canary's bare `bash` (WSL launcher); fixed in #149, released 2026-10-18.
Detail: `.claude/handoff-3d213381-9717-4755-b743-9b2b101ebce9.md` (2026-10-17 deep)

#### 2026-10-15 (deep) — 3d213381
4.3.13 released; 4.3.14–4.3.17 chained (#139–#142). Hook `if` field closed; statusline shows
prompt-cache misses; echo-heading FP fixed. Two HOOK_AUTHORING notes.
Detail: `.claude/handoff-3d213381-9717-4755-b743-9b2b101ebce9.md` (2026-10-15 deep)
