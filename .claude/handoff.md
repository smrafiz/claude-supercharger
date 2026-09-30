# Handoff — claude-supercharger

The project's carry file: **one per project, tracked in git, read first by a fresh
session on any machine.**

### Current State
*Verified 2026-09-30, session `3d213381`.*

- **Released: v4.1.22** (block-ledger secret masking, #70). v4.1.20 router fix
  (#68), v4.1.21 prompt hooks skip harness text + router hint removed (#69).
- **Master `14f9936` is ahead of v4.1.22**: #71 fp-triage tool, #72 selfmod FPs.
  The v4.1.23 stage FAILED: #71 broke test-list-hooks and test-python-encoding.
- **CI test gate was broken 2026-09-16..09-29**: `run.sh | tee` without pipefail
  reported green with failures. Fix is on branch `fix/fp-triage-ci` together
  with the #71 follow-ups. Merge it, then stage v4.1.23.
- **Machine A (this box): INSTALLED v4.1.22.** Its block ledger still holds one
  secret line written before v4.1.22 (user decides scrub/rotate).
- **Machine B**: unknown. Update to the latest release (v4.1.19 hang fix).
- **Open**: radius-apps guard-push.mjs misses `env/sudo/nohup/timeout git push`
  (fix drafted; needs a session in that repo).

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

#### 2026-09-27 — 3d213381
Traced /sc-status's "recent blocks" to their transcripts and found two shipped defects:
lesson-record saved dashboards/tables as lessons and fed itself (#48), and the claim
gate read `failed=0` as a failure — nearly all its blocks were false (#49). Both caught
a regression in their first draft only by replaying real transcripts. Staged v4.1.15.
Detail: `.claude/handoff-3d213381-9717-4755-b743-9b2b101ebce9.md`

