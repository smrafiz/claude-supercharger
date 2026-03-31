# Roadmap — Claude Supercharger

Zero-code vision: every feature works out of the box. No JSON editing, no scripting, no config files. Pick options, get value.

## v1.1 — Feedback & Polish

- **Session analytics hook** — Track tokens used per session, log to ~/.claude/supercharger/stats.json. Show trends via claude-check ("Avg session: 45K tokens, down 38% since install")
- **Role effectiveness tuning** — Refine role configs based on real-world usage. Are the token economy rules actually reducing output? Which rules get ignored by Claude?
- **Stack auto-detection** — Read package.json/Cargo.toml/requirements.txt during install, auto-suggest relevant MCP servers (e.g., detected Prisma → offer Prisma MCP)
- **Hook toggle command** — `bash tools/hook-toggle.sh safety off` to temporarily disable a hook without editing JSON. Re-enable with `on`. Status shown in claude-check
- **Compaction intelligence** — Enhanced compaction-backup hook that summarizes key decisions before /compact, not just raw transcript backup

## v1.2 — More Roles & Personas

- **Designer role** — UI/UX focus, design system awareness, accessibility checks, component naming conventions
- **DevOps role** — Infrastructure focus, Dockerfile best practices, CI/CD awareness, security scanning
- **Researcher role** — Citation-heavy output, literature review structure, methodology rigor, reproducibility
- **Freelancer role** — Client communication, scope management, time tracking awareness, deliverable checklists
- **Custom role builder** — `bash tools/create-role.sh` interactive wizard: pick traits from existing roles, set token targets, name it. Generates a role .md file and deploys to rules/

## v1.3 — Smart MCP Management

- **MCP health check** — Verify installed MCP servers actually respond (npx dry-run or version check). Flag broken/outdated servers in claude-check
- **MCP server updates** — `bash tools/mcp-update.sh` checks for newer versions of installed MCP packages
- **Project-scoped MCP** — Detect project type and suggest project-level MCP servers (e.g., Supabase project → Supabase MCP). Install to .claude/settings.json at project level
- **MCP usage tips** — After install, generate a cheat sheet: "Try these prompts to test your MCP servers: 'Look up React useEffect docs' (Context7), 'Search for CSS grid examples' (DuckDuckGo)"

## v1.4 — Team & Sharing

- **Team presets** — `bash tools/export-preset.sh` exports current config (mode, roles, MCP servers) as a shareable .supercharger file. `bash tools/import-preset.sh team.supercharger` applies it
- **Project-level config** — `.supercharger.json` in project root that auto-applies roles and MCP servers when Claude Code opens that project
- **Org guardrails** — Stricter safety rules for enterprise: block all external network calls, enforce code review before commit, mandatory test runs
- **Onboarding mode** — First-time Claude Code user? Supercharger detects no prior config and runs an interactive tutorial explaining each feature as it installs

## v1.5 — Intelligence Layer

- **Prompt rewriter hook** — Instead of just warning about vague prompts, automatically enhance them. "Fix the bug" → adds file context, recent git changes, error logs from terminal
- **Context budget monitor** — Live tracking of context usage. At 50%, suggest what to drop. At 70%, auto-suggest /compact with a pre-built summary of what to preserve
- **Learning mode** — Claude tracks which of your prompts get best results and suggests prompt improvements over time. Stored locally in ~/.claude/supercharger/learnings.json
- **Multi-session memory** — Use the Memory MCP server to build a persistent project knowledge base. Key decisions, architecture choices, and coding patterns survive across sessions automatically

## Principles

Every feature must:
1. **Work without code** — No editing config files, no scripting, no CLI flags beyond what install.sh already offers
2. **Be reversible** — Clean uninstall, no orphaned files, backup before any change
3. **Respect the user** — No telemetry, no external calls, no data leaves the machine
4. **Stay lightweight** — Bash + Python 3 only, no npm install, no compiled binaries
5. **Add measurable value** — If you can't show a before/after improvement, don't ship it
