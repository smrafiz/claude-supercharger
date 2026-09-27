# Handoff — claude-supercharger

The project's carry file: **one per project, tracked in git, read first by a fresh
session on any machine.**

### Current State
*Verified 2026-09-27, session `3d213381`.*

- **v4.1.16 RELEASED** (`5df31df`). #53: the sensitive-read rule cut a reader's args
  at the first `|` even inside quotes. A grep for `process.env` with a regex
  alternation was denied as a dotenv read (FP), and a real credential file after a
  quoted `|` was never scanned (FN).
- **v4.1.15 RELEASED** (`77ff207`): #48 lesson-record junk/self-feed; #49 claim gate
  read `failed=0` as a failure.
- **CI (#51, #52, #54): Windows runs on master pushes only; superseded runs cancel.**
  Merge PRs on Linux/macOS green (~11 min). Before `promote`, wait for master's
  Windows run at the release base (`rel^`); the rel run's Windows is SKIPPED and
  promote accepts that (#54). Promote a staged rel BEFORE merging anything else.
- `master` = `72dad8d`, 0 open PRs.
- **Machine A (this box): INSTALLED v4.1.16**, verified by grepping `_READER_ARGS`.
  One stale git stash here ("release.sh copy of #54"), identical to master: drop it.
- **Machine B**: unknown. Update straight to the latest release.

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

#### 2026-09-24 — 3d213381
Released **v4.1.14**. Audited all 33 commands, research first: /learn rules never
resurfaced (Jaccard 0.00), /reflect lessons never reached the next session (loader
reads 4 lines), /why's filter was inverted, /profile ignored per-project config.
Fixed the rm bypass (#44) after a 21k-command replay caught a false positive, and
the mtime-ranked handoff loader (#45). New /design-review.
Detail: `.claude/handoff-3d213381-9717-4755-b743-9b2b101ebce9.md`

#### 2026-09-23 — 3d213381
Released **v4.1.12** and **v4.1.13**. Upstream-tracker sweep found a selfmod gap
(#36); a DB-CLI coverage audit found 36/49 destructive commands allowed (#37). Both
fixes were checked by replaying real transcript commands OLD vs NEW hook — which
caught a first #36 fix that would have shipped 34 false positives. Rebuilt
`/multi-review`, `/security`, `/audit` from web+GitHub research (#38–#40).
Detail: `.claude/handoff-3d213381-9717-4755-b743-9b2b101ebce9.md`

#### 2026-09-22 (later) — 75a954fe
Released **v4.1.11** and shipped a regression in it: the commit stamp added by
#33 compares an 8-char local abbreviation against a 7-char remote, so every check
reports a phantom update. #35 fixes it and wants **v4.1.12 promptly**. Ten static
grep assertions passed while it was broken — only a round-trip test could fail.
Also closed the economy question by measurement (45–48%) and found that an output
style cannot replace `economy.md` because styles miss subagents.
Detail: `.claude/handoff-75a954fe-40c2-4f49-9693-c7687c0468cd.md`

