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

### Hook Toggle Tool
`bash tools/hook-toggle.sh safety off` — temporarily disable a hook without editing JSON. Re-enable with `on`. Status shown in claude-check.

*New tool: tools/hook-toggle.sh (~60 lines)*

---

## v1.4 — More Roles & Detection

### New Roles
- **Designer** — UI/UX focus, design system awareness, accessibility checks, component naming
- **DevOps** — Infrastructure, Dockerfile best practices, CI/CD, security scanning
- **Researcher** — Citations, literature review structure, methodology rigor, reproducibility

### Stack Auto-Detection
Read `package.json` / `Cargo.toml` / `requirements.txt` / `go.mod` during install:
- Auto-suggest relevant MCP servers (Prisma project → Prisma MCP)
- Auto-detect framework for developer role hints (Next.js vs Express vs Django)
- Show detected stack in claude-check

### MCP Usage Tips
After install, generate a cheat sheet:
- "Try: 'Look up React useEffect docs' (Context7)"
- "Try: 'Search for CSS grid examples' (DuckDuckGo)"
- Shown in install summary and claude-check

---

## v1.5 — Team & Sharing

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

### Prompt Rewriter Hook
Instead of just warning about vague prompts, enhance them:
- "Fix the bug" → adds file context, recent git changes, error logs
- Requires opt-in (Full mode only)

### Multi-Session Memory
Use Memory MCP server to build persistent project knowledge base:
- Key decisions, architecture choices, and patterns survive across sessions
- Automatically populated from session summaries
- Queryable: "What did we decide about auth?"

### Session Analytics
Track tokens per session, log to `~/.claude/supercharger/stats.json`:
- Show trends in claude-check ("Avg session: 45K tokens, down 38% since install")
- Identify which economy tier saves the most per role

---

## Principles

Every feature must:
1. **Work without code** — no editing config files, no scripting, no CLI flags beyond install.sh
2. **Be reversible** — clean uninstall, no orphaned files, backup before any change
3. **Respect the user** — no telemetry, no external calls, no data leaves the machine
4. **Stay lightweight** — Bash + Python 3 only, no npm install, no compiled binaries
5. **Add measurable value** — if you can't show a before/after improvement, don't ship it
