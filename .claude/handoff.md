# Handoff — claude-supercharger

The project's carry file: **one per project, tracked in git, read first by a fresh
session on any machine.**

### Current State
*Verified 2026-10-19 12:33Z, session `3d213381`.*

- **Released: v4.3.23** (master `77b61f9`). Installed v4.3.23 on Machine A; `/sc-health` 100/100.
  4.3.23 (#161): per-repo commit types via `git config supercharger.commitTypes`; health fails
  Security on `IS_DEMO` or `disableAllHooks`.
- **In flight (Machine A, launchd `sc.finish.4324`):** `~/.cache/sc-finish-4.3.24.sh` → `.result`:
  merge #162 (core guards `onFailure:"block"` on Claude Code >= 2.1.295; 8 guards made executable,
  plugin users never ran them; overrun records add session id + command hash), release 4.3.24.
  Then merge this docs PR (rebase: both append to `docs/HOOK_AUTHORING.md`).
- **Follow-ups:** plugin `hooks.json` support for `onFailure` unverified; extend the flag to other
  guards only after a full replay of each; star-keeper needs its `commitTypes` set (user).
- **Release recipe:** batch PRs; detached job under `launchctl submit` with an EXIT trap that
  `launchctl remove`s its label; merge without `--delete-branch`; PR gate = run on head SHA + both
  `Test suite` checks by name. A failed job does not retry: fix, push, relaunch.
- **Machine A:** 4 stashes + many worktrees under `.claude/worktrees/`; drop only on user's say-so.
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

#### 2026-10-13 (deep) — 3d213381
Released 4.3.6, 4.3.7 (GitSpawn/Chaindrop/GhostSplice), 4.3.8 (secret-alert attribution, six FPs);
4.3.9 (install-by-rename) in flight. 4.3.7 needed a retry: PR CI skips Windows.
Detail: `.claude/handoff-3d213381-9717-4755-b743-9b2b101ebce9.md` (2026-10-13 deep)
