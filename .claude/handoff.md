# Handoff — claude-supercharger

The project's carry file: **one per project, tracked in git, read first by a fresh
session on any machine.**

### Current State
*Verified 2026-10-15, session `3d213381` (resumed as `d9c52617`).*

- **Released: v4.3.13** (#136 audit follow-ups, #137, #138). master = `6166890` (#139 and #135 merged).
  Installed v4.3.13 on Machine A (CLAUDE.md header).
- **In flight (Machine A):** one finish job per release, chained by `~/.cache/sc-finish-<ver>.result`:
  4.3.14 = #139 (package-source-guard asks on a custom index), 4.3.15 = #140 (four Bash writes to
  settings.json past selfmod), 4.3.16 = #141 (statusline: cold prompt cache, recent miss cause),
  4.3.17 = #142 (echo text is data when its output reaches the terminal). #142 PR CI green on both OSes.
- **Closed:** hook `if` field (no hook qualifies; see HOOK_AUTHORING "The hook `if` field").
- **Known, not fixed:** after a resume, path-guard denies the new scratchpad (only SessionStart sees the
  new session id). A `dropdb` deny on a python heredoc in plinth (2026-10-15 10:23), not investigated.
- **Release recipe:** one detached finish job + ONE completion notice ("do not monitor"). Merge one at a
  time; never edit the main checkout while a job runs; the job's merge deletes the PR's worktree; PR CI
  skips Windows. A release creating its tag mid-suite fails the 3 `release: --dry-run` tests locally.
- **Machine A:** 4 stashes + many worktrees under `.claude/worktrees/`; drop only on user's say-so.
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

#### 2026-10-12 — 3d213381
4.3.3 (/sc-mcp-audit, gate skip) and 4.3.4 (live `!` context in sc-status/why/perf, Swift
toolchain hint) released; each via one detached finish job, gate skipped on green master.
Detail: `.claude/handoff-3d213381-9717-4755-b743-9b2b101ebce9.md` (2026-10-11 deep)
