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

- **master `cf6d6d8`**, clean tree. **Released: v4.1.9** — nothing unreleased.
- **One open PR: #22** (economy.md owns output length), held by choice pending the
  measurement below, not by CI.
- **v4.1.9 contents**: install-scanner bypass closed (security — `cd app && npm i
  <pkg>` previously reached neither the credibility check nor the vulnerability
  audit), the documented `eco <tier>` switch made real with one owner for the tier,
  plus the carry file and the economy-layer doc correction.
- **Machine A (the box this was written on)**: updated to v4.1.9 and verified by
  behaviour, not by the version stamp — both install gates and the tier-switch parse
  are present in `~/.claude/supercharger/hooks/`. `webstorm` MCP is disconnected here
  to save ~20k tokens/session; re-enable per project if wanted.
- **Machine B: still needs `/sc-update`.** Until then the install-scanner bypass is
  closed in the repo and open where that machine works.
- awesome-claude-code **#2096 still OPEN**, `validation-passed`, no maintainer reply
  since 2026-09-16.

### The economy decision, still in progress
The tiers do not bind. Cause: `economy.md` ships as a CLAUDE.md-layer **user
message**, while Claude Code's native **output styles** change the system prompt
itself. The built-in `Concise` style already is the minimal tier, safety carve-out
included. `outputStyle: Concise` has been on since 2026-09-20.

- **Baseline to beat**: median **207** chars / mean 447, over 1,597 assistant
  messages before the switch. Compare ordinary build sessions, not research-heavy
  ones — the latter run long regardless of tier.
- If Concise binds, **#22 is superseded**: port the tiers to custom output-style
  files and drop the persuasion layer, its reinforcement hook and its 1.1k
  tokens/session together.
- Reasoning: `docs/ECONOMY-LAYER-2026-09-19.md`, Update — 2026-09-20.
- Note `eco <tier>` now genuinely switches (v4.1.9), so the two layers *can* finally
  be isolated from each other for the measurement.

### Open, not started
- **Deny reasons reach agents without attribution.** `block()` sends only the reason
  string; the `Supercharger blocked …` banner and the remediation line go to stderr,
  which the agent never sees, so a subagent can read a block as a plain failure and
  retry blindly. Measured 2026-09-17 via a subagent probe. Touches every deny message
  and the tests asserting on them — own branch. **Started next.**
- **Where else does a start-anchored exemption hide?** v4.1.7 fixed one, #24 fixed two
  more. The method that found both: ask the question of the *assumptions* a rule
  makes, not just of other call sites.

---

## Log

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

#### 2026-09-16 — 2f637411
v4.1.5 shipped (Unicode Tag Block smuggling detection). Live CI + test-count badges
replaced the hard-coded README number. awesome-claude-code #2096 updated and validated.
Detail: `.claude/handoff-2f637411-c317-43fc-9541-b496d340f09e.md`
