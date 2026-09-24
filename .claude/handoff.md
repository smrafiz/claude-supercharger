# Handoff — claude-supercharger

The project's carry file: **one per project, tracked in git, read first by a fresh
session on any machine.**

### Current State
*Verified 2026-09-24, session `3d213381`.*

- **v4.1.14 RELEASED** (`0ffa551`, 8/8 CI). `master == v4.1.14`, **0 open PRs**.
  v4.1.12 and v4.1.13 also shipped from this session (2026-09-23).
- v4.1.14 = #44 rm bypass via `/bin/rm`, busybox, `timeout`, every shell `-c`
  spelling · #45 handoff briefs picked by stated date, not mtime · #46 every
  slash command audited/upgraded (commit messages carry the research sources).
- **Machine A (this box): INSTALLED v4.1.14**, verified by grepping the new code.
- **Machine B**: unknown — update straight to v4.1.14.
- Commands are prompts, verified structurally only. The real test is running
  them on a real project (`/audit quick` on this repo was the one live trial).

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
- **Gate the Windows job to `master` and `rel/*`?** Would remove most of 10,678
  monthly minutes, but Windows caught the CRLF defect — the release gate keeps it.
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

#### 2026-09-22 — 75a954fe
Closed the economy question by measurement rather than argument: `/output-style
concise` cuts median prose 45–48% with the minimal tier already active, so the
layer never bound because of WHERE it lives, not what it says (#22). Found that a
style cannot replace it — styles miss subagents, `CLAUDE.md` does not. Fixed
version identity (#33): the updater installed master HEAD under the last release's
number, so two machines could report `v4.1.10` and run different code. Merged #31,
#32, #22, #33; updated this machine to v4.1.10.
Detail: `.claude/handoff-75a954fe-40c2-4f49-9693-c7687c0468cd.md`

#### 2026-09-21 (later) — 75a954fe
Released **v4.1.10**: every deny and ask now reaches the agent attributed, via a
single emitter, with six fail-open shapes closed behind it. Also fixed config-scan
flagging this repo's own carry file (#31) — "output styles change the system
prompt" is documentation, not an injection.
Detail: `.claude/handoff-75a954fe-40c2-4f49-9693-c7687c0468cd.md`
