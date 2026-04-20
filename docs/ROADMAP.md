# Roadmap — Claude Supercharger

---

## Shipped

### v1.0.1 — Current release

**Protection layer (9 safe mode hooks + 43 full mode hooks = 52 total)**

Safe mode hooks:
- `safety.sh` — blocks destructive commands, credential exfiltration, force-push to main
- `code-security-scanner.sh` — warns on eval(), innerHTML=, pickle.load(), SQL injection, weak crypto, hardcoded secrets
- `smart-approve.sh` — auto-approves read-only operations (Read, Glob, Grep, git status, curl GET)
- `audit-trail.sh` — JSONL log of every file write and shell command, credentials auto-redacted, 30-day rotation
- `trace-compactor.sh` — compresses large Python/Node tracebacks to 1-line summaries
- `mcp-output-truncator.sh` — caps MCP responses at 3.5K chars
- `prompt-injection-scanner.sh` — detects "ignore previous instructions" and similar patterns in MCP/web output
- `output-secrets-scanner.sh` — scans Bash/Read output for leaked credentials (AWS, OpenAI, Slack, Stripe, etc.)
- `config-scan.sh` — scans CLAUDE.md and settings.json at session start for injection patterns

Full mode adds 43 hooks across: notifications, git safety, scope/memory, learning loop, monitoring, agent routing, session/compaction, verification/quality.

**Intelligence layer (prompt-level)**
- 3-line statusline: model, project, branch, stack, economy tier, memory/scan indicators, agent, MCP, context bar, cost, rate limit
- Token economy: Standard (~30%), Lean (~45%), Minimal (~60%) — switchable mid-conversation
- Agent routing: 9 types, task-classified per prompt
- 8 roles: developer, designer, devops, pm, researcher, student, data, writer
- Slash commands: /think, /challenge, /refactor, /audit, /test, /doc
- Skill routing table: maps task types to superpowers skills
- Project config: `.supercharger.json` for team-shared settings
- Session memory: written on stop and compact, injected on next start
- Learning loop: logs blocked commands and corrections, replays at session start
- MCP profiles: light (~300 tokens), dev (~1,200), research (~1,500), full (~3,500)
- Context advisor: warns at 50%, recommends compact at 70%, minimal at 80%, critical at 90%
- Quality gates: lint after edits, TypeScript check after .ts/.tsx, verify-on-stop

**Tooling**
- `install.sh` / `uninstall.sh` — interactive + non-interactive modes, backup/restore
- `update.sh`, `economy-switch.sh`, `hook-toggle.sh`, `config-health.sh`
- `mcp-setup.sh`, `mcp-profile.sh`, `claude-check.sh`, `token-report.sh`
- `notify-toggle.sh`, `webhook-setup.sh`, `bump-version.sh`
- 287 tests passing

---

## Near term

### Adaptive economy
Auto-suggest tier changes based on context pressure. At 70% context with standard tier, suggest lean. Session-end analysis: if avg context exceeded 80% across recent sessions, suggest starting lean by default.

### Config health score
Single 0–100 score in `claude-check`: Core, Hooks, Economy, Team, Hygiene categories. Color bar with per-category breakdown and actionable suggestions.

### Session analytics
Parse Claude Code's native JSONL session files to surface daily/weekly cost, cache hit rates, economy tier ROI. Pure Python, no external service.

---

## Longer term

### Hook pipeline composer
Chain hooks into sequential pipelines. If any hook exits 2, pipeline stops. Useful for project-specific pre-flight sequences.

### Enhanced resume
Combine session memory + recent git log + modified file diffs + open GitHub issues into a single richer context block at session start.

### Learn from sessions
Analyze past conversations for repeated corrections and violated instructions. Surface patterns as suggested additions to CLAUDE.md.

---

## Principles

Every feature must:
1. **Work without code** — no editing config files, no scripting, no CLI flags beyond install.sh
2. **Be reversible** — clean uninstall, no orphaned files, backup before any change
3. **Respect the user** — no telemetry, no external calls, no data leaves the machine
4. **Stay lightweight** — Bash + Python 3 only, no npm install, no compiled binaries
5. **Add measurable value** — if you can't show a before/after improvement, don't ship it

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
