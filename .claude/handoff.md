# Handoff — claude-supercharger

The project's carry file: **one per project, tracked in git, read first by a fresh
session on any machine.**

### Current State
*Verified 2026-10-12 (evening), session `3d213381`.*

- **Released: v4.3.5** (installed on Machine A). master = `11cb752`, no open PRs at writing.
- **In flight (agent-built, worktrees under `.claude/worktrees/`):** `fix/436-security-gaps`
  (ArtifactData file_path/str_replace secret bypass, Windows `rm -rf \` + `X~1` home alias,
  ExitWorktree discard ask, `~/.mcp-auth/`) and `fix/fp-env-dns-narrowing` (~31 real-work FPs
  from check_env_file + dig/host rule). Plan: review → merge ONE AT A TIME → release 4.3.6.
  FP PR merges only if all must-still-block tests pass.
- **Parked research:** memory `candidate-features-2026-10-12` (GhostSplice, Chaindrop, GitSpawn).
- **Unverified:** `!` commands in a fresh interactive session.
- **Release recipe:** one detached finish job + ONE completion notice ("do not monitor").
  Merge PRs one at a time — a double merge cancelled HEAD's CI (4.3.5).
- **Machine A:** 4 stashes + extra worktrees; drop only on user's say-so.
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

#### 2026-10-11 (deep) — 3d213381
4.3.1 + 4.3.2 released; #112 release gate skip merged. Found/fixed $11.7M lifetime cost
over-count (two writers dropping the offset map). /sc-mcp-audit WIP on its branch.
Detail: `.claude/handoff-3d213381-9717-4755-b743-9b2b101ebce9.md` (2026-10-11 deep)
