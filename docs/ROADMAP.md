# Roadmap — Claude Supercharger

**Current: v4.3.26.** Next: **v4.4.0**, staged once its last three PRs merge. 173 registered
hooks, about 7,270 tests, CI on macOS, Linux and Windows.

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
  parallel**: the felt cost is the slowest hook (~6.8 ms measured 2026-09-06), not the chain sum.
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

## Next: v4.4.0

Scope is frozen. On master since v4.3.26 (38 commits):

- randommonicle/claude-skills intake (#184–#197); DNS-lookup timeout asks (#202)
- MCP server configs: the skill scanner knows the Roo, Cline and Claude Desktop names
  (#203), and a Bash read of one asks, as the Read tool already did (#204)
- `/sc-de-ai` (adapted from petergyang/no-ai-slop), run by the writer agent
- The Issues List reply rule (BROKEN / RISK / NOT DONE / UNKNOWN)
- Windows: the statusline cache-speedup floor is 2.0 there, where a spawn alone is ~45 ms

Waiting to merge, then the release is staged:

| PR | What |
|---|---|
| #205 | Warn when a later call names a file a guard denied this session (trackline's "workaround" check) |
| #206 | Stop a download piped into python/perl/ruby, reads of `/etc/shadow`, and content searches over `.ssh`/`.aws`/`.gnupg` |
| #207 | Nudge to compact at 200K tokens; agents use model aliases; Navigator runs on Haiku |

Release: `tools/release.sh stage minor`, CI green on every job including Windows, then
`promote 4.4.0`.

---

## After v4.4.0, in order

1. **Windows replace is not atomic.** `test-atomic-deploy.sh` now reports, rather than
   fails on, a hook briefly missing during a Windows redeploy (a torn read still fails
   everywhere). If the count stays above zero, stage the deploy with a rename that
   replaces atomically on NTFS.
2. **Bash-guard gaps from labelled benchmarks** (the three sets bundled with
   deepu105/pi-automode-classifier). One PR each:
   - archive, then upload the archive, as two chained commands
   - a command assembled from shell variables, then executed
   - an obfuscated payload run from a python heredoc (`os.system` of decoded hex)
3. **`tools/bench-chain.py`.** The script that runs a labelled command set through every
   Bash PreToolUse hook. Commit the script, not the datasets: their licences are unchecked.
4. **`commit-guard` false positives.** It denied two ordinary `git commit` / `git add`
   commands from the Rogue Security set. Find out why.
5. **Decision needed:** should a recursive delete of an absolute path outside the project,
   or of home, ask? Today it asks only when unsaved work would be lost.
6. **Bash denies in the workaround check.** #205 records only file-path tools. Add Bash
   denies if real logs show a workaround that started from one.

### Windows — finish verification, not code

Phases 1 and 2 are code-complete and gaps G1–G6 are closed and verified on a
`windows-latest` runner ([`WINDOWS-SUPPORT-PLAN.md`](WINDOWS-SUPPORT-PLAN.md) §11.1).
What remains cannot be done from CI: no toast has been observed to render, and no human
has run a full install on a Windows desktop. The README's Windows claim stays at its
current strength until one of those happens.

---

## Considered and not taken (2026-10)

| Source | Idea | Why not |
|---|---|---|
| Provost | Warn when one skill load floods the context | The Skill tool result is ~50 chars, so a hook cannot see the size; 0 injected messages over 60K chars in 80 sessions here |
| Provost | Classify each request by difficulty and risk, route to cheaper roles | Orchestration, not enforcement (principle 6); a declaration per request costs tokens |
| Provost | Acceptance gate, dispatch cost report, reviewer eval | Covered by `stop-verify`, `claim-evidence-gate`, `subagent-cost` |
| pi-automode-classifier | A local classifier model in the decision path | Probabilistic and slower; its value was the benchmark sets |
| trackline | Diff-size check | Fires late; the thresholds are guesses |
| "each rule names its consequence" | Rewrite every rule with its consequence | Unmeasured; adds bytes to every session |
| Agensi marketplace | Repackage commands as paid skills | A skill cannot ship hooks, and the product is the hooks |
| phone-harness, browser-use/video-use | — | Different domain; nothing to enforce |

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
