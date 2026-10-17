# Handoff — claude-supercharger

The project's carry file: **one per project, tracked in git, read first by a fresh
session on any machine.**

### Current State
*Verified 2026-10-17, session `3d213381` (resumed as `deabbc7a`).*

- **Released: v4.3.17.** master = `533cc6d` (#143 merged after it). Installed v4.3.17 on Machine A.
  4.3.14 #139, 4.3.15 #140, 4.3.16 #141, 4.3.17 #142 shipped today as separate releases.
- **In flight (Machine A):** ONE combined release, `~/.cache/sc-finish-4.3.18all.sh` → `.result`: merges
  #145 (plain-word unquoted grep pattern is data), #146 (event-logger logs documented fields),
  #147 (guard canary + `/sc-health`) one at a time, then one master CI and one release 4.3.18.
  Then this docs PR. Jobs run under `nohup` now: the old ones died when the session exited.
- **Closed this session:** research #2 (per-turn context: ~50 tokens, nothing to win), #1 ConfigChange
  (audit-only; blocking is silent), python-heredoc FP class (one real hit, a genuine shell-out).
- **Parked:** path-guard scratchpad deny after a resume (cause found, no linking key; memory
  `pathguard-cwd-boundary-fp`). `/sc-trust` (low value next to /sc-status + /sc-health).
- **Release recipe:** batch merges into one release when several PRs are ready: each release costs a
  ~80 min Windows master CI. One detached job + ONE notice; never edit the main checkout while it runs.
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

#### 2026-10-17 (deep) — 3d213381
4.3.14–4.3.17 released after a gist-500 CI flake stalled the chain. Built #145–#147 (grep FP,
event-logger fields, guard canary + /sc-health); batched them into one 4.3.18. Closed 3 research items.
Detail: `.claude/handoff-3d213381-9717-4755-b743-9b2b101ebce9.md` (2026-10-17 deep)

#### 2026-10-15 (deep) — 3d213381
4.3.13 released; 4.3.14–4.3.17 chained (#139–#142). Hook `if` field closed; statusline shows
prompt-cache misses; echo-heading FP fixed. Two HOOK_AUTHORING notes.
Detail: `.claude/handoff-3d213381-9717-4755-b743-9b2b101ebce9.md` (2026-10-15 deep)

#### 2026-10-13 (deep) — 3d213381
Released 4.3.6, 4.3.7 (GitSpawn/Chaindrop/GhostSplice), 4.3.8 (secret-alert attribution, six FPs);
4.3.9 (install-by-rename) in flight. 4.3.7 needed a retry: PR CI skips Windows.
Detail: `.claude/handoff-3d213381-9717-4755-b743-9b2b101ebce9.md` (2026-10-13 deep)

#### 2026-10-12 (deep) — 3d213381
4-track research sweep (coverage, upstream tracker, new attacks, own FP ledger); two agent
PRs building 4.3.6 security fixes + FP narrowing.
Detail: `.claude/handoff-3d213381-9717-4755-b743-9b2b101ebce9.md` (2026-10-12 deep)

#### 2026-10-12 (pm) — 3d213381
4.3.5 released: installer UX from a recorded pty Quick install (9s, 2 questions) + README
Supercharger app requirements. First finish job died on a cancelled master run (double merge).
Detail: `.claude/handoff-3d213381-9717-4755-b743-9b2b101ebce9.md` (2026-10-11 deep)
