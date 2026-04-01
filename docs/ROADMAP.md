# Roadmap — Claude Supercharger

Zero-code vision: every feature works out of the box. No JSON editing, no scripting, no config files. Pick options, get value.

---

## Shipped

### v1.0.0 — Foundation
- Role-based installer (5 roles: Developer, Writer, Student, Data, PM)
- 3 install modes (Safe, Standard, Full)
- 6 hooks (safety, notify, git-safety, auto-format, prompt-validator, compaction-backup)
- Guardrails (Four Laws, autonomy levels, halt conditions)
- Anti-patterns library (35 patterns)
- Existing config handling (merge/replace/skip)
- Clean uninstaller with backup restore

### v1.1.0 — Token Economy & MCP
- Tiered token economy (Standard ~30%, Lean ~45%, Minimal ~60%)
- 5 output types with per-tier rules (Code, Commands, Explanation, Diagnosis, Coordination)
- Role-aware constraints (Student floors at Standard, Writer floors at Standard)
- Mid-conversation switching (`eco lean`, `eco minimal`)
- Economy switch CLI tool
- Role-based MCP auto-configuration (3-5 zero-config servers per role)
- Advanced MCP setup tool for key-required servers

### v1.2.0 — Session Intelligence
- Enhanced clarification mode (lightweight auto-scan + scored deep interview)
- Session summary with structured handoff and paste-ready resume prompt
- Auto-summary on compaction and rate limits
- Resume tool with clipboard copy
- 93 tests passing

---

## v1.3 — Prompt Intelligence *(next)*

Inspired by [prompt-master](https://github.com/nidhinjs/prompt-master) patterns. Focus: make Claude ask better questions, remember more, and enforce quality before execution.

### Stop Conditions Framework
Add structured start/target state requirements to `guardrails.md`:
- **Starting state** — what exists now (files, state, dependencies)
- **Target state** — what "done" looks like (output files, test criteria)
- **Checkpoint output** — progress reporting after each major step
- **Forbidden actions** — files/dirs agent must not touch
- **Human review triggers** — "stop and ask before: deleting files, adding deps, touching DB"

*Pure rules addition to guardrails.md. No infrastructure.*

### Expanded Deep Interview (9 dimensions)
Upgrade from 4 to 9 scoring dimensions:

| Current (4) | Added (5) |
|-------------|-----------|
| Scope | **Input** — what data/material starts the work? |
| Success | **Output** — format, structure, deliverable type? |
| Constraints | **Audience** — who uses this? Technical level? |
| Context | **Memory** — prior decisions that must carry forward? |
| | **Examples** — reference outputs or patterns to match? |

*Update supercharger.md deep interview section.*

### Memory Block Template
Replace vague "track decisions" in Context Carry-Forward with a prescriptive format:
```
## Memory (Carry Forward)
- Stack: [tech choices locked]
- Architecture: [patterns established]
- Naming: [conventions in use]
- Forbidden: [what was rejected and why]
- What failed: [approaches tried and abandoned]
```

Auto-generated in session summaries. Claude references it after compaction.

*Update supercharger.md Context Carry-Forward section.*

### Expanded Prompt Validator
Upgrade hook from 10 checks to 20+:
- Add: no output format specified, implicit length, missing role/audience
- Add: no file scope for code tasks, template mismatch (prose to code tool)
- Add: no negative constraints ("what NOT to do"), no starting state for agent tasks
- Keep: all existing checks (vague scope, emotional, implicit reference, etc.)

*Expand hooks/prompt-validator.sh patterns.*

### Expanded Safety Hooks
Add new pattern categories to `safety.sh` beyond destructive commands and git force-push:
- **Credential leakage** — detect secrets in metadata, URLs, labels, or commit content (`/api[_-]?key|token|secret/`)
- **Unauthorized persistence** — block cron jobs (`crontab`), shell profile edits (`.bashrc`, `.zshrc`, `.profile`), SSH key additions
- **Self-modification prevention** — block agent from editing its own config (`.claude/settings.json`, `CLAUDE.md`)
- **Production reads** — warn on `kubectl exec`, `docker exec` into production (live creds leak into transcript)

*Informed by: security monitor rules from [claude-code-system-prompts](https://github.com/Piebald-AI/claude-code-system-prompts)*

### Enhanced Verification Gate
Upgrade "did tests pass?" to "is the code real?" with stub detection:
- **Existence** — file is present at expected path
- **Substantive** — content is real implementation, not placeholder (detect TODO/FIXME/placeholder/empty returns)
- **Wired** — connected to the rest of the system (imports resolve, component is used)
- **Functional** — actually works when invoked (tests pass, build succeeds)

*Pure rules addition to supercharger.md. Informed by: verification patterns from [get-shit-done](https://github.com/gsd-build/get-shit-done)*

### Package Manager Enforcement
PreToolUse hook that auto-detects the project's package manager from lockfiles and blocks the wrong one:
- `pnpm-lock.yaml` present → blocks `npm install`, `npm run`, etc.
- `yarn.lock` present → blocks `npm install`
- `uv.lock` / `poetry.lock` present → blocks raw `pip install`
- Generalizable pattern: detect convention from lockfile, enforce it deterministically

*New hook: hooks/enforce-pkg-manager.sh (~20 lines). Informed by: [Trail of Bits claude-code-config](https://github.com/trailofbits/claude-code-config)*

### Quality Gate Pipeline
Upgrade `auto-format.sh` from "run formatter" to a multi-stage quality gate:
- **Stage 1: Lint** — run project linter (`ruff`/`eslint`/`clippy`) after every edit, detect issues
- **Stage 2: Auto-fix** — apply deterministic fixes (`ruff check --fix`, `eslint --fix`)
- **Stage 3: Re-check** — if fixes introduced new issues, report to Claude for AI-powered resolution
- Max 3 iterations, then stop and report remaining issues
- Backups created before any auto-fix modification

*Upgrade hooks/auto-format.sh → hooks/quality-gate.sh. Informed by: [claude-code-quality-hook](https://github.com/dhofheinz/claude-code-quality-hook)*

### Mutation Audit Trail
PostToolUse hook that logs all write operations to a JSONL audit file:
- Tracks: file edits, git commits, package installs, file deletions
- Format: `{"timestamp", "action", "command", "status", "file_path"}`
- Stored at `~/.claude/supercharger/audit/YYYY-MM-DD.jsonl`
- Queryable: "what did Claude change yesterday?"
- Rotated automatically (keep 30 days)

*New hook: hooks/audit-trail.sh (~40 lines). Informed by: log-gam.sh pattern from [Trail of Bits claude-code-config](https://github.com/trailofbits/claude-code-config)*

### Hook Toggle Tool
`bash tools/hook-toggle.sh safety off` — temporarily disable a hook without editing JSON. Re-enable with `on`. Status shown in claude-check.

*New tool: tools/hook-toggle.sh (~60 lines)*

---

## v1.4 — More Roles & Detection

Inspired by patterns from the [awesome-claude-code](https://github.com/hesreallyhim/awesome-claude-code) ecosystem.

### New Roles
- **Designer** — UI/UX focus, design system awareness, accessibility checks, component naming
- **DevOps** — Infrastructure, Dockerfile best practices, CI/CD, security scanning
- **Researcher** — Citations, literature review structure, methodology rigor, reproducibility

### Stack Auto-Detection
Read `package.json` / `Cargo.toml` / `requirements.txt` / `go.mod` during install:
- Auto-suggest relevant MCP servers (Prisma project → Prisma MCP)
- Auto-detect framework for developer role hints (Next.js vs Express vs Django)
- Show detected stack in claude-check

*Inspired by: Context Priming (disler/just-prompt), Claude Code Infrastructure Showcase (diet103)*

### Config Validation
Enhance `claude-check.sh` with linting:
- Detect empty rule files, broken references, conflicting rules
- Warn about oversized CLAUDE.md (context waste)
- Validate hook scripts are executable and syntactically correct
- Verify MCP servers are reachable (npx dry-run)

*Inspired by: agnix (agent-sh) — linter for Claude Code agent files*

### Enhanced Statusline
Two-line status bar at the bottom of the terminal showing live session intelligence:
- **Line 1**: Model name, project folder, git branch
- **Line 2**: Context usage progress bar (color-coded: green <50%, yellow 50-79%, red 80%+), session cost ($), elapsed time, prompt cache hit rate (%)
- Uses Claude Code's `remaining_percentage` from statusline stdin JSON — no external API calls
- Pure bash + `jq`, zero-config — auto-configured by `install.sh` via `statusLine` in settings.json

*Inspired by: statusline.sh from [Trail of Bits claude-code-config](https://github.com/trailofbits/claude-code-config); context-bar.sh from [claude-code-tips](https://github.com/ykdojo/claude-code-tips)*

### MCP Usage Tips
After install, generate a cheat sheet:
- "Try: 'Look up React useEffect docs' (Context7)"
- "Try: 'Search for CSS grid examples' (DuckDuckGo)"
- Shown in install summary and claude-check

---

## v1.5 — Team & Sharing

### Profile System
Bundle role + economy + MCP into named profiles:
- `bash tools/profile-switch.sh frontend-dev` → Developer role, Lean tier, Playwright + Magic UI
- `bash tools/profile-switch.sh data-analyst` → Data role, Standard tier, DuckDuckGo
- Profiles are just JSON files in `~/.claude/supercharger/profiles/`

*Inspired by: ClaudeCTX (foxj77) — switch entire config with one command*

### Team Presets
- `bash tools/export-preset.sh` — exports config (mode, roles, economy, MCP) as `.supercharger` file
- `bash tools/import-preset.sh team.supercharger` — applies shared config
- Team lead creates once, entire team imports

### Project-Level Config
- `.supercharger.json` in project root — auto-applies roles and economy when Claude Code opens that project
- Overrides user-level config for project scope
- Version-controlled per project

### Onboarding Mode
First-time Claude Code user? Supercharger detects no prior config and runs an interactive tutorial explaining each feature during install.

---

## v1.6 — Intelligence Layer

### Context Budget Monitor
Live tracking of context usage:
- At 50% → suggest what to drop
- At 70% → auto-suggest /compact with pre-built summary of what to preserve
- At 90% → generate session summary immediately

*Builds on: check-context.sh from [claude-code-tips](https://github.com/ykdojo/claude-code-tips) — stop hook that blocks at 85% context*

### Half-Clone Tool
Clone the later half of a conversation, discarding early context to continue with a fresh token budget:
- `bash tools/half-clone.sh` — auto-detects current session, clones later half
- Triggered automatically by Context Budget Monitor at 85%
- Resume cloned conversation with `claude -r`

*Inspired by: half-clone-conversation.sh from [claude-code-tips](https://github.com/ykdojo/claude-code-tips)*

### Prompt Rewriter Hook
Instead of just warning about vague prompts, enhance them:
- "Fix the bug" → adds file context, recent git changes, error logs
- Requires opt-in (Full mode only)

### Enhanced Resume (Multi-Factor)
Upgrade `tools/resume.sh` to combine multiple context sources:
- Session summaries (existing)
- Recent git log (new commits since last session)
- Modified files diff
- Open GitHub issues on the repo
- Generate a richer, auto-assembled context block

*Inspired by: Claude Session Restore (ZENG3LD), claude-code-tools (pchalasani)*

### Multi-Session Memory
Use Memory MCP server to build persistent project knowledge base:
- Key decisions, architecture choices, and patterns survive across sessions
- Automatically populated from session summaries
- Queryable: "What did we decide about auth?"

### Learn from Sessions
Analyze past conversation history to improve CLAUDE.md files:
- Batch recent conversations, dispatch subagents to find patterns
- Surface violated instructions (need reinforcement), missing rules, outdated entries
- Suggest additions to both global and project-level CLAUDE.md

*Inspired by: review-claudemd skill from [claude-code-tips](https://github.com/ykdojo/claude-code-tips)*

### Session Analytics
Parse Claude Code's native JSONL session files (`~/.claude/projects/*/`) to build usage reports:
- Extract token counts (input, output, cache reads, cache creation), model selection, and cost per session
- Daily/weekly/monthly cost trends shown in `claude-check` ("This week: $4.20 across 12 sessions, avg 45K tokens")
- Identify which economy tier saves the most per role
- Python script reads JSONL directly — no npm, no external service, no API calls
- Historical data from all past sessions, not just current

*Informed by: [ccusage](https://github.com/ryoppippi/ccusage) — JSONL parsing approach; [claude-code-otel](https://github.com/ColeMurray/claude-code-otel) — session data format insights*

### Trace Compactor
UserPromptSubmit + PostToolUse hook that automatically compresses Python tracebacks before they enter the context window:
- Detects traceback blocks in prompts (pasted errors) and tool outputs (failed scripts)
- Replaces 250+ token stack traces with ~40 token compact summaries
- Keeps only project-relevant frames, drops stdlib/site-packages noise
- Deterministic fingerprinting for error deduplication across a session
- Pure Python, zero dependencies

*Inspired by: [claude-tools](https://github.com/tarekziade/claude-tools) — trace compactor module*

### Prompt Injection Scanner
New hook: scan MCP tool outputs and file writes for injection attempts:
- Detect prompt injection in fetched web content and written files
- 13+ regex patterns: "ignore previous instructions", role hijacking, system prompt extraction, XML/tag injection
- Invisible Unicode detection (zero-width spaces, soft hyphens)
- Advisory mode (warn, don't block) to avoid false-positive deadlocks
- Lightweight regex-based, no external dependencies

*Inspired by: parry (vaporif) — prompt injection scanner; gsd-prompt-guard.js from [get-shit-done](https://github.com/gsd-build/get-shit-done)*

---

## Ecosystem

These projects complement Supercharger — not competitors, but tools that work well alongside it:

- **[agnix](https://github.com/agent-sh/agnix)** — lint your Supercharger config files
- **[awesome-claude-code](https://github.com/hesreallyhim/awesome-claude-code)** — curated list of Claude Code tools, hooks, and skills
- **[Superpowers](https://github.com/obra/superpowers)** — engineering skills (our skills system is adapted from this)
- **[prompt-master](https://github.com/nidhinjs/prompt-master)** — prompt engineering patterns (v1.3 incorporates several)
- **[Claude Session Restore](https://github.com/ZENG3LD/claude-session-restore)** — advanced session recovery
- **[claude-code-tips](https://github.com/ykdojo/claude-code-tips)** — context bar, conversation cloning, and handoff patterns (v1.4/v1.6 incorporates several)
- **[claude-code-system-prompts](https://github.com/Piebald-AI/claude-code-system-prompts)** — Claude Code's internal system prompts, version-tracked (v1.3 safety hooks informed by security monitor rules)
- **[get-shit-done](https://github.com/gsd-build/get-shit-done)** — verification patterns and prompt injection guard (v1.3 verification gate and v1.6 injection scanner informed by these)
- **[Dippy](https://github.com/ldayton/Dippy)** — AST-based safe command auto-approval
- **[Trail of Bits claude-code-config](https://github.com/trailofbits/claude-code-config)** — opinionated defaults from a security firm: statusline, sandboxing, package manager enforcement (v1.3/v1.4 incorporates several)
- **[claude-tools](https://github.com/tarekziade/claude-tools)** — trace compactor for Python tracebacks, zero deps (v1.6 trace compactor inspired by this)
- **[claude-code-quality-hook](https://github.com/dhofheinz/claude-code-quality-hook)** — three-stage lint/fix pipeline with git worktree parallelization (v1.3 quality gate informed by this)
- **[ccusage](https://github.com/ryoppippi/ccusage)** — Claude Code usage analyzer from JSONL files, 10k+ stars (v1.6 session analytics parsing approach)
- **[claude-code-otel](https://github.com/ColeMurray/claude-code-otel)** — OpenTelemetry observability for Claude Code (session data format insights for v1.6)

---

## Principles

Every feature must:
1. **Work without code** — no editing config files, no scripting, no CLI flags beyond install.sh
2. **Be reversible** — clean uninstall, no orphaned files, backup before any change
3. **Respect the user** — no telemetry, no external calls, no data leaves the machine
4. **Stay lightweight** — Bash + Python 3 only, no npm install, no compiled binaries
5. **Add measurable value** — if you can't show a before/after improvement, don't ship it
