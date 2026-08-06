# Roadmap — Claude Supercharger

**Current: v2.26.62** — 133 hook scripts (129 registered across events; the rest are the
statusline and shared helpers), 3351 tests passing, CI green on macOS, Linux and Windows.

Per-release detail lives in [`../CHANGELOG.md`](../CHANGELOG.md) (2.10+) and
[`CHANGELOG-archive.md`](CHANGELOG-archive.md) (earlier). This file records *direction* —
what is done, what is next, and what was considered and rejected.

---

## Shipped

### Themes since v2.0

Over 440 releases, grouped by what they were actually for:

- **Security coverage** — the largest single line of work. Two adversarial hook audits
  (the v2.21 and v2.22 series) plus ongoing sweeps closed path-traversal,
  secret-exfiltration, self-modification, git data-loss, egress, MCP, skill/agent
  poisoning and prompt-injection classes. Every guard that can *loosen* the
  system (`sc-toggle`, `hook-toggle`, `trust-mcp`) is now gated behind an explicit
  confirmation, because all three were agent-invokable.
- **Per-project isolation** — scope state, security-category opt-outs, `allowPatterns` and
  `additionalRoots` are keyed per project, so one repo can no longer change another's rules.
- **Performance** — the Bash hook chain went 130 ms → 93 ms → ~72 ms by removing forks
  (`cat`, `jq`, `md5`) from hot paths. Note that Claude Code runs matching hooks **in
  parallel**: the felt cost is the slowest hook (~7.6 ms), not the chain sum.
- **Plugin distribution** — Supercharger installs as a Claude Code plugin as well as a
  classic `install.sh`; the two detect each other and refuse to double-fire.
- **Cross-platform** — `.gitattributes` LF policy, a portable hash chain, a Windows/WSL
  notification backend, and a `windows-latest` CI job.
- **Learning loop** — blocked commands, corrections and recorded lessons are replayed at
  session start (`learn-from-blocks`, `learn-from-prompts`, `lesson-record`, `lesson-recall`).

### v2.0 — "Never Be Surprised"

Cost shield (`budget-cap`, `cost-forecast`, `cache-health`, `subagent-cost`), adaptive
economy, session checkpointing, and the hook performance profiler.

---

## Near term

### Windows — finish verification, not code

Phases 1 and 2 are code-complete and gaps G1–G6 are closed and verified on a
`windows-latest` runner ([`WINDOWS-SUPPORT-PLAN.md`](WINDOWS-SUPPORT-PLAN.md) §11.1).
What remains cannot be done from CI:

- **No toast has been observed to render.** The runner proves backend selection and a
  non-error exit — not pixels.
- **No human has run a full install on a Windows desktop.**

The README's Windows claim stays at its current strength until one of those happens.

---

## Longer term

### Hook pipeline composer

Chain hooks into ordered, project-defined sequences that stop on the first exit 2.

*Status: not built, and the case for it has weakened.* Hooks already run in parallel per
event, which is why latency stayed flat as the count grew — sequencing them would give
that up. It also cuts against principle 1 below: a pipeline is a config file the user has
to author. Revisit only if a concrete project-specific pre-flight sequence turns up that
the existing event model genuinely cannot express.

### ~~Learn from sessions~~ → shipped

Repeated corrections and blocked commands are logged and surfaced at session start.

---

## Principles

Every feature must:
1. **Work without code** — no editing config files, no scripting, no CLI flags beyond `install.sh`
2. **Be reversible** — clean uninstall, no orphaned files, backup before any change
3. **Respect the user** — no telemetry, no external calls, no data leaves the machine
4. **Stay lightweight** — Bash + Python 3 only, no npm install, no compiled binaries
5. **Add measurable value** — if you can't show a before/after improvement, don't ship it

A sixth rule earned the hard way: **be an enforcement layer, not an orchestrator.**
Supercharger guards the harness around Claude. Features that instead try to direct
Claude's work — plan/ship pipelines, multi-agent scanners, workflow ceremony — have been
evaluated and rejected repeatedly. They belong in skills, not hooks.

---

## Ecosystem

Projects that work well alongside Supercharger:

- **[Superpowers](https://github.com/obra/superpowers)** — engineering skills (our skills system is adapted from this)
- **[awesome-claude-code](https://github.com/hesreallyhim/awesome-claude-code)** — curated Claude Code tools and hooks
- **[Trail of Bits claude-code-config](https://github.com/trailofbits/claude-code-config)** — opinionated defaults from a security firm
- **[ccusage](https://github.com/ryoppippi/ccusage)** — Claude Code usage analyzer from JSONL files
- **[claude-code-tips](https://github.com/ykdojo/claude-code-tips)** — context bar, conversation cloning, handoff patterns
- **[get-shit-done](https://github.com/gsd-build/get-shit-done)** — verification patterns and prompt injection guard
- **[claude-tools](https://github.com/tarekziade/claude-tools)** — trace compactor for Python tracebacks
- **[claude-code-quality-hook](https://github.com/dhofheinz/claude-code-quality-hook)** — lint/fix pipeline patterns
