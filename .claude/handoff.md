# Handoff — claude-supercharger

The project's carry file: **one per project, tracked in git, read first by a fresh
session on any machine.** `### Current State
*Verified 2026-09-22 (later), session `75a954fe`.*

- **v4.1.11 RELEASED** (`cfdc98b`) — and it carries a **known live regression**.
- **`#35` open, 7/8 (Windows running): the v4.1.11 commit stamp never matches.**
  `git rev-parse --short` returns the shortest UNAMBIGUOUS abbreviation (8 chars
  here); the API side was cut to 7. Same commit, two spellings, so **every check
  on v4.1.11 reports a phantom update and every `/sc-update` reinstalls.** Not
  destructive; it discredits the notice #33 added. **Merge #35, cut v4.1.12.**
- **Machine A (this box): v4.1.11.** Will show the phantom update until v4.1.12.
- **Machine B**: unknown. Do not update it to v4.1.11 — wait for v4.1.12.
- **The economy question is closed** (#22): `/output-style concise` cuts median
  prose **45–48%** with the minimal tier already active and reinforced. Tight
  ±60/90/120-min windows; the 55% whole-session figure is task-mix inflated.
- **A style cannot REPLACE `economy.md`** — styles miss subagents, `CLAUDE.md`
  reaches them. Both, not either. Supersedes the 2026-09-21 "port and drop" plan.
- Merged this session: #31, #32, #22, #33, #34. Tier usage all-time: 0 STANDARD,
  19 LEAN, 255 MINIMAL.

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
- **README line 52** (`economy: lean` cuts ~45%) may credit the tier for the
  style's effect. The tier's own contribution is unmeasured; 0 STANDARD turns
  exist to measure it against. Substantiate or soften — do not reuse the number.
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

#### 2026-09-21 — 75a954fe
Released **v4.1.9** (`cf6d6d8`): the install-scanner bypass, the tier-switch fix and
two doc corrections. Machine A updated and verified by behaviour. The release did NOT
reinstall the machine by itself — an assumption carried from a 2026-09-19 note, now
known to be unreliable; check the installed copy rather than trusting a promote.
Detail: `.claude/handoff-75a954fe-40c2-4f49-9693-c7687c0468cd.md`

#### 2026-09-20 — 75a954fe
Carry file introduced (#21), project-scoped only: this file, the root `CLAUDE.md`
rules for maintaining it, and `!.claude/handoff.md` un-ignored — the existing
`handoff-*.md` negation never matched it, so the one file meant to travel between
machines was the only one that could not. An earlier attempt also changed
`hooks/lib-handoff.sh` and the `/handoff` spec; that was **reverted** as out of
scope, so reader precedence is unchanged and `/handoff` still writes per-session
briefs exactly as before.

Also this session: `eco <tier>` made to actually switch and the tier given one
owner (#23); install-scanner bypass found and fixed (#24, security); economy-layer
doc corrected with the output-styles finding (#25); `outputStyle: Concise` switched
on to measure whether the native mechanism binds where `economy.md` does not.
Detail: `.claude/handoff-75a954fe-40c2-4f49-9693-c7687c0468cd.md`
