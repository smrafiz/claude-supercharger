# Handoff — claude-supercharger

The project's carry file: **one per project, tracked in git, read first by a fresh
session on any machine.** `### Current State` is replaced wholly by each `/handoff`;
`### Log` keeps the last five sessions, each linking a fuller per-session brief.

Per-machine facts are labelled as such. The file is shared; the machine is not.
Verify before repeating a claim from here — see `hooks/lib-handoff.sh` for how
readers select this file, and why mtime is not used.

---

## Current State
*Verified 2026-09-21, session `75a954fe`.*

- **master `41e59d0`**, clean. **Released: v4.1.10** — nothing unreleased.
- **Open PRs**: **#31** config-scan false positive (CI running), **#22**
  economy.md owns output length (held by choice, not by CI).
- **v4.1.10**: every decision emits through `hooks/lib-deny.sh` with attribution
  and a remedy — 39 of 40 sites, `lib-stdin.sh` the one exemption. What an agent
  receives from a block is `permissionDecisionReason` and nothing else; stderr
  reaches the human only. Six fail-open shapes closed on the way.
- **v4.1.9**: install-scanner bypass (security), `eco <tier>` made real.
- **Machine A (this box): on v4.1.9, NOT v4.1.10** — `lib-deny.sh` is absent from
  `~/.claude/supercharger/hooks/`. Needs `/sc-update`. A promote does NOT
  reinstall; that was checked for both releases.
- **Machine B**: unknown, last known a release behind. Needs `/sc-update`.
- awesome-claude-code **#2096 still OPEN**, no maintainer reply since 2026-09-16.

### The economy decision, still open
`economy.md` ships as a CLAUDE.md-layer **user message**; Claude Code's native
**output styles** change the system prompt itself, and the built-in `Concise`
style already is the minimal tier. `outputStyle: Concise` on since 2026-09-20.

- **Baseline to beat**: median **207** chars / mean 447 over 1,597 assistant
  messages. Compare ordinary build sessions, not research-heavy ones.
- If Concise binds, **#22 is superseded** — port the tiers to output-style files
  and drop the persuasion layer with its hook and 1.1k tokens/session.
- Reasoning: `docs/ECONOMY-LAYER-2026-09-19.md`, Update — 2026-09-20.

### Open, not started
- **An unexplained deny.** A `sensitive file access` block fired on a commit
  command and did not reproduce in five reconstructions. Not a known defect —
  if it recurs, capture the exact command before anything else.
- **Stacked PRs**: merging a parent and deleting its branch CLOSES the child
  rather than retargeting it. Retarget first, or keep the base branch.

---

## Log

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

#### 2026-09-17 — 75a954fe
Community research sweep → `docs/COMMUNITY-WANTS-2026-09-17.md` with plans P1–P5.
P1 fixed two real guard false positives; P2 pinned guard independence from the
harness permission layer; P3/P4 answered by measurement. Three PRs merged.
Detail: `.claude/handoff-75a954fe-40c2-4f49-9693-c7687c0468cd.md`
