# Supercharger Hook Catalog

Auto-generated from hook headers. Run `bash tools/list-hooks.sh > docs/HOOKS.md` to refresh.

## How to disable a hook

Per-project: add to `.supercharger.json`:
```json
{ "disableHooks": ["hook-name", "another-hook"] }
```

Global: add hook name to `~/.claude/supercharger/scope/.disabled-hooks` (one per line).

## Hooks

| Hook | Event | Matcher | Purpose |
|------|-------|---------|---------|
| `adaptive-economy` | UserPromptSubmit | (none) | Auto-switches economy tier based on context window usage. |
| `agent-gate` | PreToolUse | Agent | Reads the stored agent classification. Warns on mismatch but allows |
| `agent-handoff-gate` | SubagentStop | (none) | Validates sub-agent output quality before the result flows back to the parent. |
| `agent-router` | UserPromptSubmit | (none) | Classifies each user prompt and injects a routing directive into |
| `audit-trail` | PostToolUse | Bash,Write,Edit | Logs write operations to a JSONL audit file. |
| `auto-compact` | PostToolUse | (none) | Injects /compact reminders during agentic runs when context climbs. |
| `bash-output-compactor` | PostToolUse | Bash | Compresses verbose Bash output (git log, pytest/vitest/jest, npm install) |
| `budget-cap` | PostToolUse (accumulator) | (none) | Modes: |
| `cache-health` | PostToolUse | * | Flags: async | Samples cache hit rate every 5th call. Warns when degraded (<50% for 3 consecutive readings). |
| `code-security-scanner` | PreToolUse | Write,Edit | Scans content Claude is about to write for common security vulnerabilities. |
| `comment-replacement-check` | PostToolUse | Edit, MultiEdit | Detects when Claude replaces working code with comments. Advisory — injects |
| `commit-check` | PreToolUse | Bash | Validates commit messages follow conventional commit format. |
| `compaction-backup` | PreCompact | (none) | Saves conversation transcript before context compaction. |
| `confidence-gate` | PreToolUse | Edit,Write,Bash | Computes confidence score from recent tool history + signal flags; |
| `config-scan` | SessionStart | (none) | Scans project CLAUDE.md and .claude/*.md files for prompt injection patterns. |
| `context-advisor` | UserPromptSubmit | (none) | Injects context warnings and economy suggestions based on context window usage. |
| `cost-forecast` | PreToolUse | Agent | Estimates cost before an agent spawns, based on avg_per_turn from .session-cost |
| `cron-discovery` | PreToolUse | CronCreate, CronDelete, CronList | CronCreate/CronDelete/CronList are scheduled-task tool types Claude Code |
| `cwd-changed` | CwdChanged | (none) | Re-runs stack detection when working directory changes, injects updated context. |
| `dep-vuln-scanner` | PostToolUse | Bash | Runs audit after package installs and reports critical/high vulnerabilities. |
| `design-context` | PreToolUse | Write,Edit | When editing a CSS/style file, injects DESIGN.md into context if present in project root. |
| `destructive-prompt-scanner` | UserPromptSubmit | (none) | Scans the user prompt for destructive patterns and injects an |
| `detect-stack` | — | — | Usage: bash detect-stack.sh [project_dir] |
| `economy-reinforce` | UserPromptSubmit | (none) | Re-injects active economy tier rules every Nth prompt to prevent drift. |
| `elicitation-discovery` | Elicitation, ElicitationResult | * | Elicitation lets MCP servers solicit structured input from the user — a |
| `enforce-pkg-manager` | PreToolUse | Bash | Detects lockfiles and blocks the wrong package manager. |
| `env-file-guard` | PreToolUse | Bash, Read | Blocks reading/editing .env files (which typically contain credentials). |
| `event-logger` | PermissionDenied | (none) | Logs to ~/.claude/supercharger/events.log (async, no output to Claude) |
| `failure-tracker` | PostToolUse | Bash | Detects when the same command fails repeatedly and logs the pattern. |
| `file-watcher` | FileChanged | .env,.envrc,package.json,.claude/settings.json | Notifies Claude when watched files change so it doesn't act on stale assumptions. |
| `git-safety` | PreToolUse | Bash (git *) | shellcheck source=hooks/lib-suppress.sh |
| `human-approval-gate` | PreToolUse | Bash,PowerShell | Soft gate: pauses on high-risk commands and forces Claude to ask the user |
| `lazy-refactor-check` | PostToolUse | Edit, MultiEdit | Detects when Claude renames a parameter `foo` to `_foo` instead of properly |
| `learn-from-blocks` | SessionStart | (none) | Injects accumulated learnings: blocked commands, user corrections, |
| `learn-from-prompts` | UserPromptSubmit | (none) | Detects correction AND reinforcement patterns in user prompts. |
| `lesson-recall` | UserPromptSubmit | (none) | Tokenizes user prompt, computes Jaccard overlap against stored |
| `lesson-record` | Stop | * | Scans assistant's last transcript message for diagnostic markers |
| `mcp-output-truncator` | PostToolUse | mcp__ | Truncates large MCP tool responses to prevent context window flooding. |
| `mcp-tracker` | PostToolUse | mcp__ | Writes the active MCP server name to a scope file for statusline display. |
| `messagedisplay-discovery` | MessageDisplay | * | MessageDisplay is a Claude Code event (added in late-May 2026 builds) that |
| `notify-permission` | PermissionRequest | (none) | Only fires for tools not auto-approved by smart-approve. |
| `notify-stop` | Stop | * | Shows prompt + response summary with git branch. |
| `notify` | Notification | idle_prompt | shellcheck source=hooks/lib-suppress.sh |
| `output-secrets-scanner` | PostToolUse | Bash,Read | Scans tool output for leaked secrets and warns Claude not to repeat them. |
| `path-guard` | PreToolUse | Write,Edit | Hardens Write/Edit against path-based attacks: |
| `permission-denied-advisor` | PermissionDenied | (none) | Injects context when user denies a permission, so Claude stops retrying |
| `post-compact-inject` | PostCompact | (none) | After context compaction, re-injects session constraints so Claude |
| `precompact-priorities` | PreCompact | (none) | Augments the default compact prompt with fidelity rules so the |
| `project-config` | SessionStart | (none) | (no description) |
| `prompt-injection-scanner` | PostToolUse | mcp__*,WebFetch,WebSearch | Scans MCP and external tool outputs for prompt injection attempts. |
| `prompt-validator` | UserPromptSubmit | (none) | Deterministic enforcement: catches obvious anti-patterns via regex. |
| `quality-gate` | PostToolUse | Write,Edit | Stage 1: Run linter → Stage 2: Auto-fix → Stage 3: Re-check |
| `rate-limit-advisor` | UserPromptSubmit | (none) | Flags: async | (no description) |
| `reentry-detector` | UserPromptSubmit | (none) | Detects when system output (hook messages, [MEM], [CTX]) gets pasted back |
| `repetition-detector` | PostToolUse | Bash,Read | Merged from loop-detector.sh + reread-detector.sh |
| `safety` | PreToolUse | Bash, PowerShell | Per-category toggles: disable specific security categories via |
| `scope-guard` | PostToolUse (check) | Write,Edit (check) | Modes: |
| `session-checkpoint` | PostToolUse | Write,Edit,Bash | Flags: async | Writes a lightweight checkpoint for crash recovery after every file change. |
| `session-complete` | Stop | (none) | Logs session metadata on exit. Sends webhook if configured. |
| `session-end` | SessionEnd | (none) | Logs session stats and cleans up transient scope files. |
| `session-memory-inject` | SessionStart | * | Injects .claude/supercharger-memory.md into context if present. |
| `session-memory-write` | Stop | * | Writes a compressed session summary to .claude/supercharger-memory.md |
| `shell-escape-advisor` | UserPromptSubmit | (none) | Claude Code's `! <cmd>` prompt prefix runs commands directly in the user's |
| `skill-poisoning-scanner` | PreToolUse | Skill | Scans skill content for hidden shell commands, encoded payloads, |
| `slow-tool-detector` | PostToolUse | (none) | Warns Claude when a tool takes unusually long, with tool-specific thresholds. |
| `smart-approve` | PermissionRequest | (none) | Auto-approves known-safe tool calls to reduce user prompts. |
| `standards-inject` | SessionStart | (none) | Detects project stack via lib/detect_stack.py and injects matching standards |
| `statusline` | — | — | Registered via: settings.json → statusLine → { type: "command", command: "..." } |
| `stop-failure` | StopFailure | (none) | Logs API errors (rate limits, auth failures) to errors.log for diagnosis. |
| `stop-keep-going` | Stop | (none) | Activation: opt-in only — touch ~/.claude/supercharger/scope/.keep-going |
| `stop-verify` | Stop | * | Merged from verify-on-stop.sh + project-verify.sh |
| `subagent-cost` | SubagentStart,SubagentStop | (none) | Modes: |
| `subagent-discovery` | SubagentStart, SubagentStop | * | Subagent nesting now goes up to 5 levels deep (Claude Code v2.1.172). |
| `subagent-safety` | SubagentStart | (none) | Injects safety context into sub-agents spawned via the Agent tool, |
| `subagent-stop-check` | SubagentStop | (none) | Reads last_assistant_message from subagent output and flags incomplete/failed work |
| `thinking-budget` | UserPromptSubmit | (none) | Classifies prompt complexity and nudges Claude's reasoning depth. |
| `tool-call-limiter` | PreToolUse | (none) | Counts tool calls per session. Warns at 80%, blocks at cap. |
| `tool-failure-advisor` | PostToolUseFailure | (none) | Injects failure context + tool-specific hints back to Claude when any tool errors. |
| `tool-history-tracker` | PostToolUse | (none, runs on every tool) | Appends a JSONL entry per tool call to ~/.claude/supercharger/scope/.tool-history-<session_id>. |
| `tool-preferences` | PreToolUse | Bash | Reads .supercharger.json `toolPreferences` map. When Claude tries to run a |
| `trace-compactor` | PostToolUse | Bash | Compresses large Python/Node tracebacks before Claude processes them. |
| `typecheck` | PostToolUse | Write,Edit | Runs tsc --noEmit after editing .ts/.tsx files. Injects errors into context. |
| `update-check` | SessionStart | (none) | Checks for updates once per day and prints a banner if one is available. |
| `worktree-discovery` | PreToolUse | WorktreeCreate, WorktreeRemove | WorktreeCreate/WorktreeRemove are git-worktree tool types Claude Code added |

## Standalone tools

Run any of these manually:

| Tool | Purpose |
|------|---------|
| `tools/agent-report-tail.sh` | Claude Supercharger — Agent Report Recovery |
| `tools/bump-version.sh` | Claude Supercharger — Version Bump Tool |
| `tools/cache-clear.sh` | Claude Supercharger — Cache Clear Tool |
| `tools/claude-check.sh` | Claude Supercharger — Installation Health Check |
| `tools/compress-memory.sh` | Claude Supercharger — Memory File Compressor |
| `tools/config-health.sh` | Claude Supercharger — Scored Installation Health Check |
| `tools/economy-switch.sh` | Resolve source directory (tools/ → repo root) |
| `tools/hook-doctor.sh` | Claude Supercharger — Hook Doctor |
| `tools/hook-new.sh` | Claude Supercharger — New Hook Scaffolder |
| `tools/hook-perf.sh` | Claude Supercharger — Hook Performance Profiler |
| `tools/hook-toggle.sh` | Claude Supercharger — Hook Toggle Tool |
| `tools/list-hooks.sh` | Claude Supercharger — Hook Catalog Generator |
| `tools/mcp-profile.sh` | Claude Supercharger — MCP Profile Switcher |
| `tools/mcp-setup.sh` | set -eo pipefail |
| `tools/notify-toggle.sh` | Claude Supercharger — Desktop Notification Toggle |
| `tools/profile-switch.sh` | set -euo pipefail |
| `tools/release.sh` | Claude Supercharger — Release Automation |
| `tools/scope-cleanup.sh` | Claude Supercharger — Scope State Cleanup |
| `tools/session-analytics.sh` | Claude Supercharger — Session Analytics |
| `tools/supercharger.sh` | Claude Supercharger — Capability Overview |
| `tools/token-report.sh` | Claude Supercharger — Session Token Report |
| `tools/update.sh` | Claude Supercharger — Smart Updater |
| `tools/webhook-setup.sh` | set -eo pipefail |

---

Generated by `tools/list-hooks.sh`. Last run: see git history of this file.
