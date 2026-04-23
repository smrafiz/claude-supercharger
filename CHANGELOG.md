# Changelog

## Contents

- [2.3.4] - 2026-04-23 — /profile slash command (show/switch performance profile mid-conversation); perf profile shown in tools/supercharger.sh status screen. 107 tests passing.
- [2.3.3] - 2026-04-23 — SUPERCHARGER_PROFILE=fast tier (skips 8 analytics hooks, keeps quality-gate + typecheck + dep-vuln-scanner); /cache-clear slash command + tools/cache-clear.sh with --dry-run. 107 tests passing.
- [2.3.2] - 2026-04-23 — /cache-stats slash command (typecheck/quality-gate cache state); fix CI version mismatch (lib/utils.sh + tools/supercharger.sh were missed in v2.3.0/v2.3.1 bumps). 406 tests passing.
- [2.3.1] - 2026-04-23 — Post-v2.3.0 fixes: atomic cache writes in typecheck + quality-gate (tempfile + os.replace); prune stale cache entries for deleted files on write; per-project profile via .supercharger.json ("profile": "minimal"); /perf slash command (hook timing report with suggestions); SUPERCHARGER_PROFILE docs in README. 406 tests passing.
- [2.3.0] - 2026-04-23 — Hook performance: 7 optimizations across lib-suppress.sh, typecheck.sh, quality-gate.sh, statusline.sh. SUPERCHARGER_PROFILE=minimal env var skips 11 high-latency non-security hooks. sha256 hash-cache in typecheck + quality-gate (skip tsc/lint on unchanged files). $EPOCHREALTIME timing (zero fork). in-memory disabled-hooks cache (eliminates grep fork). economy.md scan skipped when .economy-tier is fresh. jq_or_python() wrapper prevents double fork on jq-less systems. Boris Cherny workflow rules adapted: Demand Elegance, Autonomous Bug Fixing guardrails, staff-engineer verification check. 406 tests passing.
- [2.2.3] - 2026-04-23 — Audit fixes: add missing # Event: headers to 4 hooks (event-logger, git-safety, safety, scope-guard); fix /design + /multi-review + /reflect + agent-handoff-gate from R&D pass; CHANGELOG pre-stable separator to resolve duplicate version tags; 3 new credits (awesome-claude-design, awesome-llm-apps, claude-code-best). 401 tests passing.
- [2.2.2] - 2026-04-23 — Security/correctness audit: fix shell injection in rate-limit-advisor (heredoc interpolation) and subagent-cost (file path interpolation); fix prompt-injection-scanner indentation bug; fix session-checkpoint cost parsing (JSON not line-based); fix PCRE (?i) in grep -E; fix duplicate install step label; proper JSON escaping in test helper; tighten hook-toggle test assertion. 392 tests passing.
- [2.2.1] - 2026-04-22 — Add /interview command (structured requirements gathering with AskUserQuestion, recommended options) and /devlog command (living architecture journal). 392 tests passing.
- [2.2.0] - 2026-04-22 — Slash command overhaul: removed /test, /doc, /refactor (redundant); added /handoff (session resume brief), /security (OWASP review), /stuck (debug loop breaker), /scope (pre-flight gate), /pr (one-step PR). 8 commands total. 388 tests passing.
- [2.1.0] - 2026-04-22 — User-facing improvements: session-analytics --subagents per-agent cost breakdown; per-project hook overrides via disableHooks in .supercharger.json; smarter compaction guidance (session-specific preservation); cost in desktop stop notifications; stop-verify suggests specific test command (npm/pnpm/pytest/cargo) based on stack detection. Performance: lib-suppress.sh timing gated behind profiling sentinel (saves 28ms/hook); budget-cap.sh Python calls 6→2; jq for field extraction in thinking-budget + cost-forecast; .economy-tier cached at SessionStart. 380 tests passing.
- [2.0.1] - 2026-04-22 — Fix budget-cap usage parsing (tool_response.usage nesting); fix session-memory-write crash on clean repos (grep exit 1 with pipefail); compress anti-patterns.yml 856→531 tokens; add 24-scenario end-to-end integration test suite; 369 tests passing.
- [2.0.0] - 2026-04-22 — "Never Be Surprised": 10 new hooks, 1 new tool, 4 upgraded hooks across 3 waves. Wave 1 (Cost Shield): budget-cap with session cost tracking and optional hard stop, cost-forecast before agent spawns, cache-health monitor warns on cache degradation (safe mode), subagent-cost per-agent JSONL logging. Wave 2 (Smart Adaptation): adaptive-economy auto-switches tier at context thresholds with session-history learning, thinking-budget calibrates reasoning depth by task complexity, rate-limit-advisor warns when projected exhaustion <30m with statusline burn projection. Wave 3 (Session Intelligence): session-checkpoint crash-resilient state on every file change, enhanced session-memory-inject with checkpoint recovery + diff/cost/failures enrichment, hook-perf CLI profiler. Shared: lib-suppress.sh timing instrumentation, project-config.sh parses budget/autoEconomy/thinkingControl/forecastTurnsPerAgent. Statusline: budget display line 3, cache health coloring line 2, burn rate projection. Hook counts: safe 10 (+1), full+dev 64 (+10). 345 tests passing (+52), 0 failures.
- [1.0.6] - 2026-04-21 — Session analytics: daily cost/cache rollup + per-project breakdown (session-analytics.sh); 7d summary in claude-check.sh; remove confusing guardrails-template.yml line from health check
- [1.0.5] - 2026-04-21 — Fix project-scope .supercharger-debug not working: $PWD unreliable in hook context; refactor lib-suppress.sh with init_hook_suppress(dir) function; all 12 hooks now re-call with actual project dir after reading stdin; session-memory-inject now reads stdin for cwd
- [1.0.4] - 2026-04-21 — Fix UserPromptSubmit/SubagentStart hooks showing [CTX] banner in UI; switch to hookSpecificOutput.additionalContext for silent injection; systemMessage reserved for infrequent events (SessionStart, PostCompact, FileChanged)
- [1.0.3] - 2026-04-21 — Hook output suppressed by default (suppressOutput:true); debug flag to re-enable: ~/.claude/supercharger/scope/.debug-hooks (global) or .supercharger-debug (project); lib-suppress.sh shared helper; README debug FAQ entry
- [1.0.2] - 2026-04-21 — Fix all hook JSON output schemas (systemMessage replaces invalid hookSpecificOutput/additionalContext); config health score in claude-check (0-100); fix hardcoded version in claude-check; bump-version now covers plugin files
- [1.0.1] - 2026-04-20 — Tests for file-watcher/event-logger/dep-vuln-scanner (287 total); HOOK_AUTHORING.md; CONTRIBUTING.md; Git Bash md5sum order fix
- [1.0.0] - 2026-04-20 — Initial stable release: 52 hooks, statusline (eco tier, mem restore, scan alerts), 9 agent types, adaptive token economy, code/secrets/injection scanners, session memory, MCP profiles, CVE-2025-59536 guard

### Pre-stable Releases (development numbering — predates stable v1.0.0)

- [3.6.11] - 2026-04-19 — Add Claude Code marketplace plugin metadata; dead-code carveout anti-pattern; fix hook counts in tests
- [3.6.10] - 2026-04-19 — Add session memory (writes .claude/supercharger-memory.md on Stop, injects at SessionStart)
- [3.6.9] - 2026-04-19 — Add project-verify hook (.claude/verify.sh runs on Stop, feeds failures back); compress subagent safety injection 26→4 lines
- [3.6.8] - 2026-04-19 — Fix credential leakage in blocked-commands log; redact PASSWORD/TOKEN/SECRET before logging; truncate to 120 chars; reduce injection cap 15→10
- [3.6.7] - 2026-04-19 — Compaction instructions, skill trigger table, cache-ordered economy.md, MCP output truncator, supercharger.md lazy-load
- [3.6.6] - 2026-04-19 — MCP profile tiers (light/dev/research/full), paths: lazy-loading for role rules, ~5k token/session reduction
- [3.6.5] - 2026-04-19 — Add rubber-duck, diff-preview, teach-me opt-in rules
- [3.6.4] - 2026-04-16 — Opt-in checkpoint mode, humanized README, OpenCode port plan
- [3.6.3] - 2026-04-15 — CVE-2026-35021 file path check, obfuscation detection, role anti-patterns, smart-approve expansion, statusline resilience
- [3.6.2] - 2026-04-15 — Self-teaching: 30-day log rotation, dedup, capped 15-entry injection; smart-approve Write/Edit in project dir
- [3.6.1] - 2026-04-15 — Smart-approve: Write/Edit in project dir, npm run/build/dev, build tools, script runners; statusline resilient 3-line output
- [3.6.0] - 2026-04-15 — Optimize all 9 agents: add color, example blocks, fix tools (researcher+web, general+bash), planner haiku→sonnet
- [3.5.9] - 2026-04-15 — Fix CI: statusline tests for 3-line output, actions/checkout v5, time display hours fix
- [3.5.8] - 2026-04-15 — Agent name normalization in statusline (safety net), simplified rate limit format
- [3.5.7] - 2026-04-15 — Normalize dispatched agent name (dash→space, title case), Agent: label in statusline
- [3.5.6] - 2026-04-15 — 3-line statusline with labels, Agent: prefix, Usage: Session/Weekly format, agent-gate multi-field detection
- [3.5.5] - 2026-04-15 — Fix statusline line 2 vanishing (rate limits type error), idle notification 60s cooldown
- [3.5.4] - 2026-04-15 — Fix false idle notifications: 60s cooldown, filter transient states
- [3.5.3] - 2026-04-15 — Fix statusline token math (input-only context, session cumulative output), project-scoped stack cache, agent-gate re-registration
- [3.5.2] - 2026-04-15 — Fix agent-gate re-registration for correct dispatched agent in statusline; credit token-optimizer and CCNotify
- [3.5.1] - 2026-04-15 — Statusline: exact context size, rate limits with countdown, lines changed; reread-detector mtime check; token economy CLAUDE.md improvements; README update
- [3.5.0] - 2026-04-15 — Token optimization: loop detector (catches repeated tool calls, saves 10-50K tokens) and re-read detector (nudges Claude to use cached file knowledge)
- [3.4.0] - 2026-04-15 — Code security scanner: warns on eval(), innerHTML, SQL injection, pickle, hardcoded secrets, weak crypto in Write/Edit content
- [3.3.2] - 2026-04-13 — Fix statusline null-safe .get() chains, remove app-switching from notifications, tighten learning false positives
- [3.3.1] - 2026-04-13 — 3 notification types (task complete, input needed, permission request), idle cooldown fix, README update, credit claude-code-warp
- [3.3.0] - 2026-04-12 — Enhanced self-teaching: positive reinforcement detection, repeated failure tracker with live nudge, 4-signal learning system
- [3.2.1] - 2026-04-12 — Session-scoped agent/MCP scope files — multiple Claude sessions no longer share agent names in statusline
- [3.2.0] - 2026-04-12 — 3-layer injection defense: SessionStart config scan + PostToolUse output secrets scanner, smart-approve persistent session rules, /effort and subagent model tips
- [3.1.0] - 2026-04-12 — Self-teaching: learn from blocked commands + user corrections, MCP server name in statusline, structured deny reasons, verify-on-stop, statusline token/cache fix
- [3.0.7] - 2026-04-12 — /permissions wildcard tip in README, verify-on-stop hook, statusline cached token fix
- [3.0.6] - 2026-04-12 — Warn-only Stop hook (alerts when files modified but no test/build ran), statusline token count fix (cached tokens included), structured deny reasons
- [3.0.5] - 2026-04-12 — Fix statusline token count (include cached tokens), remove broken Stop prompt hook, structured deny reasons in safety/git-safety, notification matcher filter
- [3.0.4] - 2026-04-12 — LLM-evaluated Stop hook for verification, structured deny reasons in safety/git-safety, notification matcher filter, smart-approve decision reasons
- [3.0.3] - 2026-04-09 — Fix update.sh hang, quality-gate lint loop early-break, shellcheck SC2259 fix, all CI green
- [3.0.2] - 2026-04-09 — Fix notify.sh RCE, bash-native regex in git-safety/enforce-pkg-manager/safety.sh, jq-first in scope-guard/project-config, dedup update-check, injection scanner grep consolidation, compaction-backup rotation
- [3.0.1] - 2026-04-09 — Performance: grep consolidation (~36 forks eliminated in safety.sh), bash-native regex in agent-router, fix audit-trail POSIX regex bug, fix quality-gate race condition, statusline token display improvements
- [3.0.0] - 2026-04-09 — Major pruning: 24→17 hooks, 3→2 install modes, forced agent dispatch removed, 7 tools cut, context-monitor+adaptive-economy merged
- [2.0.17] - 2026-04-09 — v1.7: adaptive economy, session analytics CLI, config health score tool
- [2.0.16] - 2026-04-09 — v1.6 Intelligence Layer: context budget monitor, trace compactor, prompt injection scanner
- [2.0.15] - 2026-04-08 — Economy tier injected into every prompt context; GitHub MCP uses gh extension; quality-gate eslint glob fix
- [2.0.14] - 2026-04-08 — Fix statusline showing classifier name instead of dispatched agent (.agent-classified / .agent-dispatched split)
- [2.0.13] - 2026-04-08 — New hooks: PermissionRequest smart-approve, SubagentStart safety injection, SessionEnd cleanup; git-safety rewrites force-push instead of blocking
- [2.0.12] - 2026-04-08 — Fix economy tier detection in update.sh (loose substring → Active Tier heading regex)
- [2.0.11] - 2026-04-08 — Deploy tools/ and lib/ to install target so economy-switch runs without local repo
- [2.0.10] - 2026-04-08 — Audit log redaction expanded, macOS CI runner, shellcheck lib/tools/tests, agent name normalization (title case, dash→space)
- [2.0.9] - 2026-04-08 — Fix awk field variable bug in project agent parsing, 273 passing
- [2.0.8] - 2026-04-08 — Fix agent-gate mismatch detection regression, test suite green
- [2.0.7] - 2026-04-08 — Fix project agent CWD resolution and statusline agent name
- [2.0.6] - 2026-04-08 — Project agent priority routing in agent-router.sh
- [2.0.5] - 2026-04-07 — Refactor: shared cmd-normalize, dynamic uninstall command list
- [2.0.4] - 2026-04-07 — Consistency audit: hook safety, install accuracy, version placeholder
- [2.0.3] - 2026-04-07 — Stack assumption verification, .claudedocs gitignored
- [2.0.2] - 2026-04-07 — Stabilization: per-step token display, redundant safety rules removed, MCP deferred loading confirmed
- [2.0.1] - 2026-04-07 — Performance: jq fallback, background quality-gate, stack cache, daily audit rotation
- [2.0.0] - 2026-04-07 — New features: conventional commits, GitHub MCP, /test, /doc, safety improvements
- [1.9.8] - 2026-04-07 — Notification filtering, statusline updates, install step count fix
- [1.9.7] - 2026-04-07 — Desktop notification prompt in installer
- [1.9.6] - 2026-04-07 — Statusline per-prompt token display with in/out breakdown
- [1.9.5] - 2026-04-07 — Session token accumulation, statusline prompt/session display
- [1.9.4] - 2026-04-07 — Token usage display in statusline, install detection, feature doc rewrite
- [1.9.3] - 2026-04-06 — README rewrite, agent gate fix, examples accuracy
- [1.9.2] - 2026-04-06 — Context size reduction, README accuracy fixes
- [1.9.1] - 2026-04-06 — README accuracy fixes, update integrity, cost feedback loop
- [1.9.0] - 2026-04-06 — Hook JSON key fix, echo pipe safety
- [1.8.0] - 2026-04-06 — Enforced agent routing
- [1.7.6] - 2026-04-06 — Scope Guard hook, hook count fix
- [1.7.5] - 2026-04-06 — Auto-update banner, sound-only notifications
- [1.7.4] - 2026-04-06 — update.sh: detect and preserve config silently
- [1.7.0] - 2026-04-03 — Custom Commands, Architect agent, reviewer hierarchy
- [1.6.0] - 2026-04-02 — 8 Focused Agents, Stack Detection, Project Agent Scaffolder
- [1.5.0] - 2026-04-02 — Profile System, Project-Level Config, Team Presets
- [1.4.0] - 2026-04-02 — Enhanced Statusline, 3 New Roles, Config Validation
- [1.3.0] - 2026-04-02 — Package Manager Enforcement, Quality Gate, Audit Trail
- [1.2.0] - 2026-04-01 — Session Summary, Resume Tool
- [1.1.0] - 2026-04-01 — Tiered Token Economy
- [1.0.0] - 2026-03-31 — Initial Release

---

## Pre-stable Detailed Notes (development era — predates stable v1.0.0)

## [2.0.9] - 2026-04-08

### Fixed
- **Project agent parsing** — `parse_agent_field` in `agent-router.sh` was not passing the `field` variable to awk (`-v field="$field"` missing). `name` and `description` were never extracted from agent frontmatter — project agents were silently never detected. Smoke tests caught this.

### Added
- **Agent routing smoke tests** — `tests/test-agent-routing-project.sh` covers: project agent injection, fallback when no agents dir, skipping nameless agents, `workspace.current_dir` priority over `$PWD`, description truncation and JSON validity. 273 passing, 0 failing.

---

## [2.0.8] - 2026-04-08

### Fixed
- **agent-gate mismatch detection** — route file was overwritten with dispatched agent before mismatch check, so warning never fired. Now reads stored route first, then updates file. Mismatch warnings restored.
- **Test suite** — `test-economy.sh` PM row assertion updated to match renamed `Project Manager` table entry. 253 passing, 0 failing.
- **README test badge** — corrected to 253 (actual passing count).

---

## [2.0.7] - 2026-04-08

### Fixed
- **Project agent CWD resolution** — `agent-router.sh` was using `$PWD` to locate `.claude/agents/`, which resolves to the hook process directory, not the open project. Now parses project path from hook JSON payload (`workspace.current_dir` / `cwd`), falling back to `$PWD`. Project agents now auto-activate correctly.
- **Statusline agent name** — `agent-gate.sh` now updates the route file on every agent dispatch, not just the first. Statusline now shows the actual dispatched agent (e.g., `shopify-integration-engineer`) instead of the global pre-classification.

---

## [2.0.6] - 2026-04-08

### Added
- **Project agent priority routing** — `agent-router.sh` now detects `.claude/agents/` in the current project, parses `name` and `description` from each agent's frontmatter, and injects them into `additionalContext` with an explicit precedence signal. Project agents take priority over global classification when they better fit the task. Conflict rule: if a project agent and global agent would both handle the same request, the project agent wins. Falls back to global routing when no project agents are present.

---

## [2.0.5] - 2026-04-07

### Fixed
- **Uninstall completeness** — `uninstall.sh` now derives command removal list dynamically from `configs/commands/*.md`; `/test` and `/doc` are no longer left behind after uninstall

### Changed
- **Shared normalization** — extracted 7-line command normalization block into `hooks/cmd-normalize.sh`; `safety.sh`, `git-safety.sh`, `enforce-pkg-manager.sh`, and `commit-check.sh` now source it

---

## [2.0.4] - 2026-04-07

### Fixed
- **Version placeholder** — `configs/universal/CLAUDE.md` now uses `{{VERSION}}` instead of hardcoded `v1.8.0`; substituted at install time alongside `{{ROLES}}` and `{{MODE}}`
- **Silent hook failures** — `quality-gate.sh` and `prompt-validator.sh` now capture stdin before parsing; missing `python3` no longer causes all checks to silently pass
- **Hook consistency** — `agent-gate.sh` aligned to jq-first + python3 fallback pattern; `notify.sh`, `session-complete.sh`, `update-check.sh` updated to `set -euo pipefail`
- **Install accuracy** — step counter now shows "Step 3 of 6" for economy tier; summary derives command names dynamically from `configs/commands/`
- **Block message format** — `enforce-pkg-manager.sh` aligned to multi-line Reason/Command format used by all sibling hooks
- **Test badge** — corrected from 253 to 207

---

## [2.0.3] - 2026-04-07

### Fixed
- **Stack assumption verification** — SessionStart message now prompts Claude to ask before proceeding if any detected stack assumptions seem wrong.
- **Gitignore** — added `.claudedocs/` to prevent per-user audit reports from being committed.

---

## [2.0.2] - 2026-04-07

### Changed
- **Statusline token display** — settled on per-step tokens with in/out breakdown after 3 accumulation approaches proved unreliable due to statusline rendering architecture. Simple, accurate, real-time.
- **CLAUDE.md safety rules** — replaced 3 redundant lines with 1: "Destructive commands are blocked at the shell level." Hooks enforce these already.
- **README context cost** — clarified MCP tool definitions are deferred by default in Claude Code 2.x (no hidden overhead).
- **MCP deferred loading** — confirmed already active by default. No config change needed or possible from settings.json.

---

## [2.0.1] - 2026-04-07

### Performance
- **jq-first JSON parsing** — safety.sh, git-safety.sh, enforce-pkg-manager.sh, commit-check.sh now try `jq` (~5ms) before falling back to `python3` (~35ms). Saves ~90ms per Bash tool call.
- **agent-router.sh** — merged 2 python3 calls into 1 (jq for stdin, printf for JSON output). Saves ~35ms per prompt.
- **quality-gate.sh background execution** — linters now run in a background subshell. Hook returns immediately. Eliminates 300-2000ms blocking per Write/Edit call.
- **Linter timeout** — all linter invocations prefixed with 30s timeout (gtimeout/timeout). Prevents indefinite stalls on large projects.
- **audit-trail.sh daily rotation** — `find -mtime +30 -delete` now gated behind daily timestamp check instead of running on every tool call.
- **Stack detection cache** — project-config.sh writes detected stack to `.stack-cache` at SessionStart. statusline.sh reads from cache instead of re-parsing package.json on every render.

---

## [2.0.0] - 2026-04-07

### Added
- **Conventional commit enforcement** — new `commit-check.sh` hook blocks non-conventional commit messages (`feat:`, `fix:`, `chore:`, etc.). Handles `-m "..."`, `-m '...'`, and HEREDOC patterns. Allows `--amend` and merge commits.
- **GitHub MCP server** — auto-installed for developer role. Uses `@modelcontextprotocol/server-github` via npx. Works zero-config with `gh` CLI auth.
- **/test command** — generate unit tests with framework detection, coverage targets, and automatic test execution.
- **/doc command** — generate documentation with style detection (JSDoc, docstrings, rustdoc) and scope inference.
- **Generalist agent fallback** — unmatched prompts now route to Steve Jobs (Generalist) instead of getting no agent.

### Fixed
- **Package manager bypass** — `sudo npm install` in pnpm project was not blocked. Added prefix stripping (sudo/command/env) matching safety.sh pattern.
- **Git safety gaps** — added blocks for `git branch -D main/master`, `git clean -f`, `git stash drop`, `git stash clear`, and `git checkout -- .` variant.
- **Commit-check HEREDOC handling** — uses Python regex to extract messages from HEREDOC patterns, not just simple `-m "..."` strings.

---

## [1.9.8] - 2026-04-07

### Fixed
- **Phantom notifications** — `notify.sh` was firing on all 7 Claude Code notification types. Now filters to only `idle_prompt` (Claude waiting) and `worker_permission_prompt` (subagent needs permission). Silently exits for auth, computer-use, and elicitation events. Uses payload's message field instead of hardcoded string.
- **Install step count** — updated from "4 of 4" to "5 of 5" and README from "Four questions" to "Five questions" (notification prompt was added in v1.9.7).
- **README statusline description** — now mentions active agent display and per-prompt token usage with in/out breakdown.

---

## [1.9.7] - 2026-04-07

### Added
- **Desktop notification prompt** — installer now asks users to choose notification mode: On (popup), Sound (beep only), or Off. Applies via flag files used by `notify.sh`. Also available as `--notify on|off|sound` CLI arg for non-interactive installs. Notification preference shown in install summary.

---

## [1.9.6] - 2026-04-07

### Changed
- **Statusline token display** — shows per-prompt tokens with input/output breakdown: `180 tok (1 in / 179 out)`. Removed session accumulation (was delayed by one render, confusing to users). Cost display still tracks session total.

---

## [1.9.5] - 2026-04-07

### Fixed
- **Session token accumulation** — statusline renders multiple times per response; token counts were duplicated on each re-render. Now tracks last-seen values and only accumulates on new responses.
- **Statusline shows both session and prompt tokens** — `session: 1.2K tok | prompt: 180 tok` format replaces the single combined display.
- **Session token cleanup** — `.session-tokens` file cleared on session end via scope-guard.sh.

---

## [1.9.4] - 2026-04-07

### Added
- **Token usage in statusline** — shows total tokens with input/output breakdown (e.g. `1.2K tok (1.1K in / 96 out)`). Updates per response.
- **Full agent name in statusline** — shows `Agent: Sherlock Holmes (Detective)` instead of just `Sherlock`.
- **Install detection** — `install.sh` detects existing installation and offers Update (preserves config) vs Reinstall. Non-interactive installs bypass the prompt.

### Fixed
- **Statusline syntax error** — nested double quotes in a Python comment inside `python3 -c` block broke bash quoting. Caused statusline to disappear after install.
- **MCP setup prompt** — no longer blocks non-interactive installs (full args provided).

### Changed
- **Feature recommendations doc** — rewrote entirely. Removed 11 items that already exist, removed hallucinated URLs, added 11 genuine recommendations with effort/risk/context-cost assessment.

---

## [1.9.3] - 2026-04-06

### Changed
- **README rewrite** — restructured around honest value hierarchy. Safety layer presented as the core product; agents, roles, economy tiers clearly labeled as instructional (prompt-based, not enforced). Removed marketing language and unverifiable claims.
- **Agent gate** — changed from hard block (exit 2) to advisory warning (exit 0). Session routing still works via the system message directive; the gate no longer prevents legitimate subtask dispatches (e.g., spawning a Critic for code review during a Writer-routed session).

### Fixed
- **Agent name labels** — all 8 agent routing examples now match source code names exactly: (Detective), (Critic), (Engineer), (Writer), (Scientist), (Architect), (Strategist), (Analyst).
- **SSH keys claim** — scoped from "SSH keys" to specific commands blocked (`ssh-keygen`, `ssh-add`, `ssh-copy-id`).
- **Block message format** — 3 examples in docs/examples.md now match actual hook output (`"Supercharger blocked this command.\n  Reason: ..."` instead of single-line format).
- **Compaction summary claim** — examples.md now states summary is "prompted, not enforced."

---

## [1.9.2] - 2026-04-06

### Changed
- **Context size reduction** — reduced per-conversation token load by ~1,200 tokens (24%). guardrails.md: removed rules duplicated in CLAUDE.md (761 chars saved). supercharger.md: compressed deep interview, session summary, memory block, removed duplicate anti-pattern section (3,214 chars saved). anti-patterns.yml: consolidated overlapping patterns (804 chars saved). All 8 role files: removed Token Efficiency footers already defined in economy.md (~640 chars saved).

### Fixed
- **README rm -rf claim** — now specifies which targets are blocked (root, home, parent traversal), not "all rm -rf".
- **README quality gate claim** — now states conditionality: Developer role, Standard/Full install mode.
- **README agent fallback example** — replaced non-matching Steve Jobs example with a working Sun Tzu pattern.
- **README zero-dependency claim** — scoped to "core install"; added note that MCP servers use npx at runtime.
- **README compaction backup claim** — accurately describes hook saving raw transcript; structured summary is prompted, not guaranteed.

---

## [1.9.1] - 2026-04-06

### Fixed
- **README MCP table** — Designer role was incorrectly listed alongside Developer for Playwright. Designer only receives Magic UI; Playwright is Developer-only. Split into two rows.
- **README economy claims** — Removed unverifiable percentage reduction figures (`~45%`, `~60%`). Economy tiers are prompt instructions, not enforced constraints. Column renamed from "Reduction" to "Target"; values updated to intent language (`concise output`, `minimal output`, etc.).
- **README economy headline** — "cuts your costs in half" replaced with "instructs Claude to prioritize concise output".
- **`tools/update.sh` integrity** — Added GitHub API commit SHA verification before executing `install.sh` from cloned repo. Mismatch aborts update and cleans up temp directory.

### Added
- **Session cost feedback loop** — `hooks/session-complete.sh` now persists session cost and active economy tier to `~/.claude/supercharger/.last-session-cost` on every Stop event. `hooks/project-config.sh` reads this at SessionStart and injects "Last session cost: $X (economy: lean)" into Claude's system context, giving a live signal instead of a static promise.

---

## [1.9.0] - 2026-04-06

### Fixed
- **Critical hook JSON key bug** — `safety.sh`, `git-safety.sh`, and `enforce-pkg-manager.sh` were reading `input.command` instead of `tool_input.command`. All three safety hooks were silently passing every command through (read empty string, exited 0). Also fixed `input.file_path` → `tool_input.file_path` in `quality-gate.sh`, `audit-trail.sh`, and `scope-guard.sh` check mode.
- **echo pipe safety** — replaced `echo "$VAR" | grep/python3` with `printf '%s\n' "$VAR"` across all 7 affected hooks to prevent flag injection when variable content starts with `-n` or `-e`.
- **Test JSON format** — updated `tests/helpers.sh` `run_hook()` and all inline hook assertions in `tests/test-hooks.sh` to use `tool_input.*` keys, matching actual Claude Code hook protocol.

---

## [1.8.0] - 2026-04-06

### Added
- **Agent routing** — `agent-router.sh` (UserPromptSubmit) classifies the first prompt using ordered regex rules and injects a mandatory routing directive into Claude's context. Covers 8 agent patterns; ambiguous prompts fall through silently.
- **Agent gate** — `agent-gate.sh` (PreToolUse/Agent) enforces the classification: blocks dispatch of the wrong agent (exit 2). If no route was set by the router, latches on the first agent Claude dispatches and enforces from there. Achieves ~99% correct routing without any user behavior change.
- **13 new tests** — `tests/test-agent-router.sh` (9 cases) and `tests/test-agent-gate.sh` (6 cases).

### Fixed
- `scope-guard.sh` clear mode now also removes `.agent-route` so routing state resets cleanly on session end.
- Regex priority: `write a function/test/class/script` now correctly routes to Tony Stark (Engineer) before the generic `write` pattern reaches Ernest Hemingway (Writer).
- Routing patterns extended: `add a`, `should I use`, `should I go with` now match correctly.
- README routing examples corrected to match actual regex behavior.
- Install test hook count assertions updated (standard: 13, full: 17).

---

## [1.7.6] - 2026-04-06

### Added
- **Scope Guard hook** — `scope-guard.sh` runs in three modes: `snapshot` (SessionStart), `contract` (UserPromptSubmit), `check` (PostToolUse). Warns when writes exceed declared scope.

### Fixed
- `count_installed_hooks` was undercounting by 3 in standard mode and 1 in full mode (missing scope-guard entries and scope-guard clear).

---

## [1.7.5] - 2026-04-06

### Added
- **Auto-update banner** — `update-check.sh` hook prints a banner at SessionStart when a newer version is available (checks once per 24 hours, non-blocking).
- **Sound-only notification mode** — notify hook supports sound-only output without desktop popup.

### Changed
- `--check` flag now shows changelog summary.

---

## [1.7.4] - 2026-04-06

### Fixed
- `update.sh` no longer re-runs the full installer on update — detects installed mode and preserves user config silently.

---

## [1.7.0] - 2026-04-03

### Added
- **4 Custom Commands** — `/think`, `/refactor`, `/challenge`, `/audit`. Reusable slash-command workflows installed to `~/.claude/commands/` on every install.
  - `/think [problem]` — structured 5-step reasoning: clarify → inventory → hypotheses → stress-test → decide
  - `/refactor [target]` — systematic code quality analysis across 7 dimensions (complexity, duplication, naming, error handling, coupling, testability, dead code)
  - `/challenge [decision]` — adversarial stress-test: assumptions → failure modes → strongest alternative → blind spots → verdict
  - `/audit [target]` — inconsistency sweep across naming, patterns, documentation, interfaces, and structure
- **Architect agent** — global (`~/.claude/agents/architect.md`) + project template (`configs/project-agent-templates/architect.md`). Design-before-code specialist: produces design plans with explicit decisions and rejected alternatives. Does NOT write implementation code.
- **Architect added to all project scaffolds** — `tools/init-agents.sh` now includes architect in every stack's agent set (after orchestrator)
- **Evidence threshold in debugger** — both global and project template: must have exact error + source line + 2-level call chain before forming any hypothesis
- **Reviewer RULE 0/1/2 hierarchy** — both global and project template: production safety > conformance > structural quality. Replaces generic CRITICAL/SHOULD/CONSIDER.
- **Failure-mode reasoning** — reviewer findings now require "When X fails, Y happens, resulting in Z" — not vague "this could cause issues"
- **Thinking economy** — added to code-helper, general, debugger, and implementation project agents (frontend, backend, systems). Output conclusions only.
- **Cleanup attestation** — added to done checklists: code-helper, frontend-engineer, backend-engineer, systems-engineer. No debug statements in submitted code.
- **`tools/init-context.sh`** — scaffolds `CLAUDE.md` index stubs in subdirectories. Skips node_modules/dist/build/vendor. Keeps stubs under 200 tokens.
- 23 new tests (227 total): architect file + frontmatter, commands existence + content, reviewer severity model, evidence threshold, project template upgrades, commands on install

### Changed
- `install.sh` now deploys `configs/commands/*.md` to `~/.claude/commands/`
- `install.sh` deploys `architect.md` as part of agent set (9 agents total)

## [1.6.0] - 2026-04-02

### Added
- **8 Focused Agents**: Auto-installed to `~/.claude/agents/` — `code-helper`, `debugger`, `writer`, `reviewer`, `researcher`, `planner`, `data-analyst`, `general`. Each has a focused description so Claude Code invokes the right agent automatically based on task type. No selection required.
- **First-Run Welcome**: On first session after install, Claude introduces Supercharger in plain English — guardrails, verification, lean responses. Fires once, never repeats.
- **Always-On Stack Detection**: `project-config` hook now detects stack (Node/TypeScript/React, Python/Django/FastAPI, WordPress, Rust, Go, PHP) on every session start and silently tells Claude — no `.supercharger.json` required.
- **Statusline Stack Indicator**: Line 1 of the status bar now shows detected stack (e.g. `[sonnet] my-project | master | TypeScript, React`)
- **Human-Readable Hook Messages**: Blocked commands now show plain-English reason + "Tell me to confirm if you want to proceed" — no raw error strings
- **Project Agent Scaffolder**: `bash tools/init-agents.sh` — auto-detects stack, scaffolds `.claude/agents/` with project-specific agents (orchestrator, frontend-engineer, backend-engineer, debugger, code-reviewer, qa-engineer, systems-engineer). Supports `--force`, `--stack`, `--dir` flags. Merge/Replace/Cancel if agents already exist.
- **Upgraded Global Agents**: All 8 global agents rewritten with production-quality structure — Own/Read-only/Forbidden scope sections, numbered safety-first rules (Rule 0=security/safety), escalation blocks, done checklists. Reviewer uses opus, planner uses haiku.
- 64 new tests (204 total): agent file existence, frontmatter validation, model assignments, first-run welcome, welcome flag creation, no-repeat logic, stack detection via project-config, human-readable block messages, agent deploy on install

### Changed
- `project-config` hook always runs (previously exited early with no `.supercharger.json`)
- `safety.sh` and `git-safety.sh` block messages restructured: `Reason:` label, command echo, confirmation instruction
- install.sh deploys agents from `configs/agents/` to `~/.claude/agents/`

## [1.5.0] - 2026-04-02

### Added
- **Profile System**: Bundle role + economy + MCP into named profiles. 5 built-in (frontend-dev, backend-dev, data-analyst, tech-writer, team-lead) + custom profiles. `bash tools/profile-switch.sh <name>`
- **Project-Level Config**: `.supercharger.json` in project root auto-applies roles, economy, and project hints on session start via SessionStart hook
- **Team Presets**: Export/import config as `.supercharger` files. `bash tools/export-preset.sh` / `bash tools/import-preset.sh`
- **Onboarding Mode**: First-time users get a welcome guide during install explaining what each step does
- `project-config` SessionStart hook added to standard+ mode
- 7 new tests (140 total)

### Changed
- Standard mode now includes `project-config` hook (7 hooks for standard+developer, was 6)
- claude-check shows active profile and detects `.supercharger.json` in current directory
- claude-check hook list includes `project-config`
- claude-check role loops check all 8 roles (was 5)

## [1.4.0] - 2026-04-02

### Added
- **Enhanced Statusline**: 2-line status bar showing model, project, git branch, context usage bar (color-coded), session cost, duration, and prompt cache hit rate
- **Stack Auto-Detection**: Detects language, framework, package manager, test framework, and build tool from project files (Python, JS/TS, Rust, Go ecosystems)
- **3 New Roles**: Designer (UI/UX, accessibility, design systems), DevOps (IaC, Docker, CI/CD, security scanning), Researcher (citations, methodology, evidence-based)
- **Config Validation**: claude-check lints empty rule files, oversized CLAUDE.md, non-executable hooks, syntax errors in hook scripts, malformed settings.json
- **MCP Usage Tips**: Post-install cheat sheet showing example prompts for installed MCP servers
- Designer gets Magic UI MCP server; DevOps and Researcher get DuckDuckGo Search
- 15 new tests (133 total)

### Changed
- Roles expanded from 5 to 8 (added Designer, DevOps, Researcher)
- Economy constraints added for new roles: Designer/DevOps unrestricted, Researcher floors at Standard
- Mode switching updated for 8 roles in CLAUDE.md template
- claude-check updated with statusline check, stack detection, config validation sections, version 1.4.0

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
