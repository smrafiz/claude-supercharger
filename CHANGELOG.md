# Changelog

## [1.3.0] - 2026-04-02

### Added
- **Package Manager Enforcement**: PreToolUse hook blocks wrong package manager based on lockfile detection (pnpm-lock.yaml, yarn.lock, uv.lock, poetry.lock, bun.lockb)
- **Quality Gate Pipeline**: PostToolUse hook runs 3-stage lint→auto-fix→re-check after every edit (ruff, eslint, clippy, rustfmt, gofmt, Prettier, Black)
- **Mutation Audit Trail**: PostToolUse hook logs all mutations (file edits, git commits, installs) to JSONL with 30-day rotation at `~/.claude/supercharger/audit/`
- **Hook Toggle Tool**: `bash tools/hook-toggle.sh safety off` — enable/disable any hook without editing JSON
- **Credential Leak Detection**: Safety hook blocks API keys, AWS AKIA patterns, GitHub `ghp_` tokens, OpenAI `sk-` keys in commands
- **SSH Key Operation Blocking**: Safety hook blocks `ssh-keygen`, `ssh-add`, `ssh-copy-id`
- **Shell Profile Protection**: Safety hook blocks writes to `.bashrc`, `.zshrc`, `.profile`, `.bash_profile`
- **Self-Modification Prevention**: Safety hook blocks agent from writing to `.claude/settings.json` or `.claude/CLAUDE.md`
- **Stop Conditions Framework**: Guardrails now include start/target state, checkpoints, forbidden actions, and human review triggers
- **Deep Interview expanded**: 4→9 dimensions (added Input, Output, Audience, Memory, Examples) with Critical vs Conditional scoring
- **Enhanced Verification Gate**: 4-level check — Existence → Substantive → Wired → Functional
- **Memory Block Template**: Structured context carry-forward format for multi-turn tasks after compaction
- 10 new prompt validator checks (11-20): output format, implicit length, file scope, negative constraints, starting state, template mismatch, role/persona, unscoped "all", version pinning, error context
- 25 new tests (118 total)

### Changed
- Safety hook expanded with 4 new blocking categories (credentials, persistence, self-modification, production reads)
- Prompt validator expanded from 10 to 20 checks
- Developer role hook changed from `auto-format` to `quality-gate` (3-stage pipeline replaces single formatter)
- Standard mode now includes `enforce-pkg-manager` and `audit-trail` hooks (6 hooks total, was 4)
- Install modes description updated (Standard now mentions quality gate, pkg enforcement, audit trail)
- claude-check updated with new hook names and v1.3.0 version

## [1.2.0] - 2026-04-01

### Added
- **Enhanced clarification mode**: Lightweight scan on all prompts + scored deep interview (4 dimensions, threshold-based questioning)
- **Session summary**: Structured handoff block with decisions, files changed, and paste-ready resume prompt
- **Auto-summary triggers**: Fires on "session summary" keyword, context compaction, and rate limits
- **Resume tool**: `bash tools/resume.sh` — shows latest summary, copies resume prompt to clipboard
- **Resume --list/--show**: Browse and view past session summaries
- **Summaries directory**: `~/.claude/supercharger/summaries/` — created by compaction hook
- 7 new tests for resume tool (93 total)

### Changed
- Clarification Mode in supercharger.md upgraded from 4 bullets to two-tier system (lightweight + deep interview)
- Session Handoff now references Session Summary format
- Compaction backup hook creates summaries directory alongside transcript backup
- claude-check shows session summary count and latest file
- Uninstaller cleans up summaries directory

## [1.1.0] - 2026-04-01

### Added
- **Tiered token economy**: Standard (~30%), Lean (~45%), Minimal (~60%) reduction tiers
- **5 output types**: Code, Commands, Explanation, Diagnosis, Coordination — each with per-tier rules
- **Role-aware constraints**: Student floors at Standard, Writer floors at Standard, Student ceiling at Lean
- **Mid-conversation switching**: "eco standard", "eco lean", "eco minimal" keywords
- **Economy selection at install**: New installer step after role selection
- **Post-install switching**: `bash tools/economy-switch.sh [tier]` CLI tool
- **Universal output rules**: 7 always-on rules (no ceremony, no restating, lead with deliverable)
- New file: `configs/universal/economy.md` — single source of truth for token economy
- New file: `lib/economy.sh` — tier selection, validation, deployment logic
- New file: `tools/economy-switch.sh` — CLI for changing tiers after install
- New files: `configs/economy/standard.md`, `lean.md`, `minimal.md` — tier templates
- 18 new tests covering tier deployment, validation, constraint enforcement, and integration

### Changed
- Role configs now declare economy metadata (2 lines) instead of role-specific token rules
- CLAUDE.md template references economy.md instead of inline token rules
- supercharger.md Output Discipline section references economy.md
- Installer now has economy tier selection step
- Uninstaller cleans up economy.md

### Removed
- Inline Token Economy section from CLAUDE.md template
- Per-role Token Efficiency bullet lists (replaced with economy metadata)
- Redundant anti-pattern bullets (ceremony, repeating — now in economy.md universal rules)
- Output Discipline rules from supercharger.md (moved to economy.md)

## [1.0.0] - 2026-03-31

### New
- Role-based installer with 5 roles: Developer, Writer, Student, Data, PM
- 3 install modes: Safe, Standard, Full
- Multi-select role support (combine any roles)
- Universal CLAUDE.md (~50 lines) with verification gate and safety boundaries
- Universal rules (supercharger.md) with execution workflow and anti-pattern detection
- Guardrails system inspired by TheArchitectit/agent-guardrails-template (Four Laws, autonomy levels, halt conditions)
- 6 hooks: safety, notify, git-safety, auto-format, prompt-validator, compaction-backup
- Existing config handling: Merge / Replace / Skip for CLAUDE.md and settings.json
- MCP server setup tool (12 servers supported)
- claude-check diagnostic tool
- Clean uninstaller with backup restore
- Anti-patterns library (35 patterns)
- Non-interactive install via CLI flags (`--mode`, `--roles`, `--config`, `--settings`)
- MIT LICENSE with BSD-3 attribution for guardrails content

### Ship-Ready Fixes
- **Role prioritization:** Only selected roles deploy to `rules/` (auto-loaded); all 5 stored in `supercharger/roles/` for mode switching
- **Safety hook hardening:** Command normalization (strips `sudo`/`command`/`env`/`\` prefixes, collapses whitespace) + flag-aware `rm` detection + new patterns (fork bomb, `truncate`, `mv /`, `kill -9 -1`)
- **Git-safety hardening:** Position-independent flag matching for `--force`, `--hard`, `--clean`
- **Prompt validator expanded:** 3 → 10 checks (vague scope, multiple tasks, emotional descriptions, implicit references, etc.)
- **Anti-patterns integration:** Moved from `shared/` to `rules/` so Claude Code auto-loads the 35-pattern library
- **CLAUDE.md merge fix:** Merge mode now appends full rendered config (not just a 4-line comment)
- **CLAUDE.md template:** Added role priority line, removed dead `@` import references
- **Version consistency:** Standardized to `1.0.0` across all files
- **README trimmed:** 555 → 180 lines; overflow examples moved to `docs/examples.md`
- **Test suite added:** 57 tests covering install, uninstall, hooks (with bypass attempts), and role deployment
- **Token economy:** Concrete response length targets, upgraded output discipline, role-specific token efficiency rules, and compaction preserve/discard guidance
- **Role-based MCP servers:** Auto-configures 3-5 zero-config MCP servers based on role selection (Context7, Sequential Thinking, Memory as core; Playwright, Magic UI, DuckDuckGo as role-specific). Rewritten `mcp-setup.sh` for advanced key-required servers (GitHub, Brave, Slack, etc.). 65 tests total.

### Credits
- Inspired by SuperClaude Framework (MIT) — execution workflow patterns
- Guardrails adapted from TheArchitectit/agent-guardrails-template (BSD-3)
