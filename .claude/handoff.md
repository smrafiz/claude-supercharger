# Handoff — claude-supercharger

The project's carry file: **one per project, tracked in git, read first by a fresh
session on any machine.** `### Current State
*Verified 2026-09-22, session `75a954fe`.*

- **master `d82de7d`**, clean, **0 open PRs**. **4 commits past the `v4.1.10` tag**
  — including two real fixes (#31, #33). A release would collapse that gap.
- **Last released: v4.1.10.** #22, #31, #32, #33 all merged since.
- **The economy question is MEASURED and closed** (#22, `21d7922`). Same session,
  split at the exact `/output-style concise` timestamp, minimal tier active and
  reinforced on both sides: median **278 → ~148 chars, a 45–48% cut**, stable
  across ±60/90/120-minute windows. The whole-session figure of 55% is task-mix
  inflated — use the tight windows.
- **A style cannot REPLACE `economy.md`.** Output styles do not reach subagents;
  `CLAUDE.md` does. Porting the tiers to a style would be a subagent coverage
  regression. Correct shape is both. Supersedes the "port the tiers and drop the
  layer" plan recorded here on 2026-09-21.
- **Tier usage across every local transcript: 0 STANDARD, 19 LEAN, 255 MINIMAL.**
  Three tiers, one exercised.
- **#33 fixed version identity**: the updater installs master HEAD while `VERSION`
  only moves at release, so two machines could both report `v4.1.10` and run
  different code. Installs now carry a `.commit` stamp and `--check` compares it.
  **Unreleased** — the fix is on master, not in anyone's install.
- **Machine A (this box): v4.1.10 == `f350846`.** Verified on disk, not inferred
  (`lib-deny.sh` present, config-scan FP fix present). Now 2 commits behind master.
- **Machine B**: unknown, last known a release behind. Needs `/sc-update`.
- awesome-claude-code **#2096 still OPEN** — verified today; no maintainer reply
  since 2026-09-16, 6 comments, all bot validation.

### Decisions parked, not blocked
- **README line 52** claims `economy: lean` cuts ~45%. The measured 45% belongs to
  the output **style**, measured on top of an already-active tier; the tier's own
  contribution is unmeasured and there is no STANDARD data to measure it against.
  Substantiate or soften — do not quietly reuse the number.
- **Install the tag rather than master?** Would make a version identify code
  exactly and restore meaning to "release" — right now merging to master *is*
  shipping. Against: users stop getting fixes the moment they merge. Mitigating:
  PRs run the full 8-check matrix, so master is gated, just untagged.
- **Do not seize the output-style slot.** `outputStyle` is one field and
  `force-for-plugin` overrides the user's own choice. Ship the style file, print
  the command, let the user pick.

### Open, not started
- **An unexplained deny.** A `sensitive file access` block fired on a commit
  command and did not reproduce in five reconstructions. Not a known defect —
  if it recurs, capture the exact command before anything else.
- **Stacked PRs**: merging a parent and deleting its branch CLOSES the child
  rather than retargeting it. Retarget first, or keep the base branch.
---

## Log

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

#### 2026-09-19 — 1c65c296
v4.1.6/.7/.8 released. Economy-layer investigation: three causes, two fixed —
`economy-reinforce` now fires per turn (0/20 → 20/20), and the context-% statusline
sidecar wires three previously-inert hooks. Handoff briefs first tracked in git.
Detail: `.claude/handoff-1c65c296-96dc-4531-8bd7-02cad448bf2a.md`
