# Handoff — claude-supercharger

The project's carry file: **one per project, tracked in git, read first by a fresh
session on any machine.**

### Current State
*Verified 2026-09-30, session `3d213381`.*

- **Released: v4.1.23** (10:16 UTC): rule slimming (always-loaded 14.3 -> 11.7 KB),
  input-budget in /sc-status + /sc-doctor, fp-triage (macOS/Linux), selfmod FPs,
  CI test gate fixed. Master `b267a10` adds #80 (manual Windows run on any branch).
- **No open PRs.** Debug branch `debug/fp-triage-win` exists: never merge; delete
  once fp-triage's Windows fix lands.
- **Machine A (this box): INSTALLED v4.1.23**; ai-coding-token-optimizer skill
  installed; memory index slimmed to 14.4 KB. Its block ledger still holds one
  secret line from before v4.1.22 (user's call).
- **Machine B**: unknown. Update to v4.1.23.
- **Open**: fp-triage on Windows; radius-apps guard-push wrapper bypass.

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

#### 2026-09-30 (late) — 3d213381
v4.1.23 out after three Windows refusals (MSYS paths, hidden failure text). Input
budget built and used: 38.3 -> 27.6 KB per session here. Manual Windows CI trigger
added; fp-triage Windows debug in flight.
Detail: `.claude/handoff-3d213381-9717-4755-b743-9b2b101ebce9.md`

#### 2026-09-30 — 3d213381
Released v4.1.19-22: router and prompt hooks stop reading harness text as user
text, agent hint removed (1.1% uptake), block-ledger secret masking. Built
fp-triage, fixed selfmod FPs. Found the CI test gate green-on-failure since
09-16. Jev researched and parked.
Detail: `.claude/handoff-3d213381-9717-4755-b743-9b2b101ebce9.md`

#### 2026-09-28 — 3d213381
Research sweep (web, GitHub, upstream tracker) became six fixes (#59-#64). A history
replay that timed out led to a SECURITY bug: a bracketed `VAR=` prefix hung every
Bash guard, which fails open. Every guard change was replayed against ~48k real
commands first; three first drafts regressed and were caught that way.
Detail: `.claude/handoff-3d213381-9717-4755-b743-9b2b101ebce9.md`

#### 2026-09-27 (late) — 3d213381
Released **v4.1.17** (cron rule prose FP). Swept every real deny that depended only on
quoted or heredoc text: the real ones were search patterns scanned as shell, fixed in
#57 (unreleased). Wrote the five-fix lesson into `docs/HOOK_AUTHORING.md`.
Detail: `.claude/handoff-3d213381-9717-4755-b743-9b2b101ebce9.md`

#### 2026-09-27 (later) — 3d213381
Released **v4.1.16**: a dotenv block on a real grep traced to quoted-`|` truncation in
the sensitive-read rule, an FP and an FN in one line (#53). Moved Windows CI to master
only (~80 min per PR saved) and fixed the promote gate that change broke (#54).
Detail: `.claude/handoff-3d213381-9717-4755-b743-9b2b101ebce9.md`

