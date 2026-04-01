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

### v1.3.0 — Prompt Intelligence
- Package Manager Enforcement (lockfile-based PreToolUse hook)
- Quality Gate Pipeline (3-stage lint→fix→recheck PostToolUse hook)
- Mutation Audit Trail (JSONL logging with 30-day rotation)
- Hook Toggle Tool (enable/disable without editing JSON)
- Expanded Safety Hooks (credential leaks, SSH key ops, shell profile, self-modification)
- Expanded Prompt Validator (10→20 checks)
- Stop Conditions Framework, Enhanced Verification Gate (4-level)
- Deep Interview expanded to 9 dimensions, Memory Block Template
- 118 tests passing

### v1.4.0 — More Roles & Detection
- Enhanced Statusline (2-line: model, project, git branch, context %, cost, cache hit rate)
- Stack Auto-Detection (Python, JS/TS, Rust, Go — language, framework, package manager, test/build tools)
- 3 New Roles: Designer, DevOps, Researcher (8 total)
- Config Validation in claude-check (empty files, oversized CLAUDE.md, non-executable hooks, syntax errors)
- MCP Usage Tips in install summary
- 133 tests passing

### v1.5.0 — Team & Sharing
- Profile System — 5 built-in + custom profiles, one-command switch. *Inspired by: ClaudeCTX (foxj77)*
- Project-Level Config (`.supercharger.json` SessionStart hook)
- Team Presets (export/import `.supercharger` files)
- Onboarding Mode (first-time user guidance)
- 140 tests passing

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

## v1.7 — Automation & Learning

### Learn from Sessions
Analyze past conversation history to improve CLAUDE.md files:
- Batch recent conversations, detect user corrections and repeated patterns
- Surface violated instructions (need reinforcement), missing rules, outdated entries
- Suggest additions to both global and project-level CLAUDE.md
- `bash tools/learn-from-sessions.sh` with optional `--apply`

*Inspired by: review-claudemd skill from [claude-code-tips](https://github.com/ykdojo/claude-code-tips)*

### Smart Command Auto-Approval
PermissionRequest hook that auto-approves safe, read-only commands:
- Whitelist-based: `ls`, `git status`, `cat`, `grep`, `npm list`, etc.
- Chain-aware: `git status && rm -rf /` is NOT approved
- Redirect detection: any `>`, `tee`, pipe-to-write blocks auto-approval
- Graceful degradation if PermissionRequest event not yet supported

*Inspired by: [Dippy](https://github.com/ldayton/Dippy) — AST-based safe command auto-approval*

### Session End Handler
SessionEnd hook for cleanup and logging:
- Auto-save session summary if none was generated during session
- Log session stats to audit trail (duration, transcript size, exit reason)
- Clean up temp files older than 7 days
- Suggest learn-from-sessions when 10+ sessions have accumulated

### Subagent Monitor
SubagentStart/SubagentStop hooks to track Task tool activity:
- Log all subagent starts and stops to audit trail with duration
- Optional concurrent subagent limit (`SUPERCHARGER_MAX_SUBAGENTS` env var)
- Graceful degradation if subagent events not yet supported

### Enhanced Notifications
Enrich notification messages with project context:
- Git branch, project name, context percentage in every notification
- Platform-aware: macOS `osascript`, Linux `notify-send`
- Optional notification sounds (`SUPERCHARGER_NOTIFY_SOUND=1`)

*Inspired by: [claude-notifications-go](https://github.com/777genius/claude-notifications-go) — smart notifications with git branch display*

### Config Health Score
Single number (0-100) in claude-check showing config quality:
- 5 categories: Core (40pts), Hooks (25pts), Economy (15pts), Team (10pts), Hygiene (10pts)
- Color-coded bar chart with per-category breakdown
- Actionable suggestions for improving score

### Adaptive Economy
Auto-suggest or auto-apply economy tier changes based on context usage:
- At 50% context + standard tier → suggest lean
- At 70% context + standard tier → strongly recommend lean (or auto-apply if opted in)
- Session-end analysis: if avg context > 80% across 5 sessions → suggest starting with lean

### Hook Pipeline Composer
Tool to chain multiple hooks into sequential pipelines:
- `bash tools/hook-compose.sh --event UserPromptSubmit --chain "prompt-validator,prompt-rewriter"`
- Output of one hook feeds into the next
- Block propagation: if any hook blocks (exit 2), pipeline stops

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
- **[claude-notifications-go](https://github.com/777genius/claude-notifications-go)** — smart notifications with click-to-focus, git branch display, webhook integrations (v1.7 enhanced notifications inspired by this)
- **[claude-code-hooks](https://github.com/karanb192/claude-code-hooks)** — ready-to-use hooks with safety levels and testing patterns (v1.7 hook architecture informed by this)

---

## Principles

Every feature must:
1. **Work without code** — no editing config files, no scripting, no CLI flags beyond install.sh
2. **Be reversible** — clean uninstall, no orphaned files, backup before any change
3. **Respect the user** — no telemetry, no external calls, no data leaves the machine
4. **Stay lightweight** — Bash + Python 3 only, no npm install, no compiled binaries
5. **Add measurable value** — if you can't show a before/after improvement, don't ship it
