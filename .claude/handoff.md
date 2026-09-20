# Handoff — claude-supercharger

The project's carry file: **one per project, tracked in git, read first by a fresh
session on any machine.** `### Current State` is replaced wholly by each `/handoff`;
`### Log` keeps the last five sessions, each linking a fuller per-session brief.

Per-machine facts are labelled as such. The file is shared; the machine is not.
Verify before repeating a claim from here — see `hooks/lib-handoff.sh` for how
readers select this file, and why mtime is not used.

---

## Current State
*Verified 2026-09-20, session `75a954fe`.*

- **master `28e4a1c`**, clean tree. **Released: v4.1.8** — two merges sit on master
  unreleased (`fb75e06` carry file, `28e4a1c` tier-switch fix).
- **Open PRs**: **#24** install-scanner bypass (security; Windows CI running),
  **#25** economy-layer doc correction, **#22** economy.md owns output length.
  #22 is deliberately **held** pending the measurement below.
- **Machine A (the box this was written on)**: v4.1.8, sidecar live. `webstorm` MCP
  disconnected here to save ~20k tokens/session; re-enable per project if needed.
- awesome-claude-code **#2096 still OPEN**, `validation-passed`, no maintainer reply
  since 2026-09-16.

### The economy decision, in progress
The tiers do not bind, and the cause is understood: `economy.md` ships as a
CLAUDE.md-layer **user message**, while Claude Code's native **output styles** change
the system prompt itself. The built-in `Concise` style already is the minimal tier.
`outputStyle: Concise` was switched on here on 2026-09-20 to measure it.

- **Baseline to beat**: median **207** chars / mean 447, over 1,597 assistant messages
  before the switch. Re-measure on ordinary build sessions, not research-heavy ones.
- If Concise binds, **#22 is superseded** — port the tiers to custom output-style files
  and drop the persuasion layer, its reinforcement hook and its 1.1k tokens/session.
- Full reasoning: `docs/ECONOMY-LAYER-2026-09-19.md`, Update — 2026-09-20 (PR #25).

### Open, not started
- **Where else does a start-anchored exemption hide?** #24 fixed two hooks after
  v4.1.7 fixed one. The method that found both: ask the question of *assumptions*
  a rule makes, not just of other call sites.
- **Deny reasons reach agents without attribution** — `block()` sends only the reason;
  the `Supercharger blocked …` banner and remediation line go to stderr, which the
  agent never sees, so a subagent can read a block as a plain failure.
- **Version stamps** in recent code comments say v4.1.6/v4.1.9; sweep if the next
  release is a minor rather than a patch.

---

## Log

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

#### 2026-09-16 — 2f637411
v4.1.5 shipped (Unicode Tag Block smuggling detection). Live CI + test-count badges
replaced the hard-coded README number. awesome-claude-code #2096 updated and validated.
Detail: `.claude/handoff-2f637411-c317-43fc-9541-b496d340f09e.md`

#### 2026-09-07 — 4cf5c165
Perf figures re-measured and published after the harness fix; KNOWN-ISSUES #5 and #6
each narrowed at the shared path rather than the named call site.
Detail: `.claude/handoff-4cf5c165-6b4c-4fc4-90b3-26b9ac2769c9.md`
