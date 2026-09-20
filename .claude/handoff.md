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

- **master `8a21f63`**, clean tree, **0 open PRs**, CI green on head (8/8 incl. Windows).
- **Released: v4.1.8.** Tags v4.1.6/.7/.8 all published, nothing unreleased on master.
- **Machine A (the box this was written on)**: on v4.1.8, `lib-ctx-pct.sh` installed, sidecar live.
  The only diff against the repo is the installer's shebang rewrite
  (`#!/usr/bin/env bash` → `#!/bin/bash`) — an install-time transform, not staleness.
- **In flight**: branch `feat/merged-handoff` — this file, plus the reader precedence
  and the `/handoff` spec that maintain it. Not yet merged.
- awesome-claude-code **#2096 still OPEN**, `validation-passed`, no maintainer reply
  since 2026-09-16.

### Open questions
- **Does the prompt layer bind now that all three delivery paths work?** Testable for
  the first time since v4.1.8. Gates the opt-in decision.
- **Economy cause 3**: the layer contradicts its own tier rules — 463 bytes asking for
  terseness against ~12.1 KB asking for thoroughness. Editorial; needs a human to pick
  the one file that owns output length.
- **How many other guards carry a start-anchored exemption?** `e04fefd` fixed three
  `git commit` copies; the rest are unchecked.
- **Colleague's `additionalRoots` one-liner** — still unverified, he is unlikely to reinstall.

---

## Log

#### 2026-09-20 — 75a954fe
Merged carry file introduced: this file, `!.claude/handoff.md` un-ignored (the
existing `handoff-*.md` negation never matched it, so the one file meant to travel
between machines was the only one that could not), reader precedence in
`hooks/lib-handoff.sh` changed to own-SID → merged → newest-scoped, and the
`/handoff` spec rewritten to maintain both files. 4 assertions added, 2 red at HEAD.
Detail: this branch's commit message.

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
