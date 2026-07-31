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
| `ansi-escape-guard` | PreToolUse | Write, Edit, MultiEdit | A raw ANSI escape written into a file can carry a HIDDEN payload: the SGR conceal |
| `audit-trail` | PostToolUse | Bash,Write,Edit | Logs write operations to a JSONL audit file. |
| `auto-compact` | PostToolUse | (none) | Injects /compact reminders during agentic runs when context climbs. |
| `bash-injection-scanner` | PostToolUse | Bash | Scans Bash command OUTPUT for prompt-injection / instruction-override markers. |
| `bash-output-compactor` | PostToolUse | Bash | Compresses verbose Bash output (git log, pytest/vitest/jest, npm install) |
| `budget-cap` | PostToolUse (accumulator) | (none) | Modes: |
| `bulk-exfil-guard` | PreToolUse | Bash | safety-detect.py's upload arms (_NETWORK_UPLOADS / _CLOUD_UPLOADS) only fire when |
| `cache-health` | PostToolUse | * | Flags: async | Samples cache hit rate every 5th call. Warns when degraded (<50% for 3 consecutive readings). |
| `cloud-cli-destructive-guard` | PreToolUse | Bash | Cross-channel parity with mcp-destructive-guard: that hook ASKS before a |
| `code-security-scanner` | PreToolUse | Write,Edit | Scans content Claude is about to write for common security vulnerabilities. |
| `comment-replacement-check` | PostToolUse | Edit, MultiEdit | Detects when Claude replaces working code with comments. Advisory — injects |
| `commit-guard` | PreToolUse | Bash | ONE hook, three independent self-gating checks on `git commit`. Merged from the |
| `compaction-backup` | PreCompact | (none) | Saves conversation transcript before context compaction. |
| `confidence-gate` | PreToolUse | Edit,Write,Bash | Computes confidence score from recent tool history + signal flags; |
| `config-scan` | SessionStart | (none) | Scans project CLAUDE.md and .claude/*.md files for prompt injection patterns. |
| `config-weakening-notice` | CwdChanged | (none) | Entering a directory whose `.supercharger.json` disables security categories or |
| `context-advisor` | UserPromptSubmit | (none) | Injects context warnings and economy suggestions based on context window usage. |
| `cost-forecast` | PreToolUse | Agent | Estimates cost before an agent spawns, based on avg_per_turn from .session-cost |
| `critical-infra-guard` | PreToolUse | Write,Edit,MultiEdit,NotebookEdit | Forces an explicit human confirm before Claude edits a critical-infra file — |
| `cron-discovery` | PreToolUse | CronCreate, CronDelete, CronList | CronCreate/CronDelete/CronList are scheduled-task tool types Claude Code |
| `cwd-changed` | CwdChanged | (none) | Re-runs stack detection when working directory changes, injects updated context. |
| `dep-vuln-scanner` | PostToolUse | Bash | Runs audit after package installs and reports critical/high vulnerabilities. |
| `dependency-preflight` | SessionStart | — | install.sh refuses to proceed without `jq` and `python3` (install.sh:8, :25). A |
| `design-context` | PreToolUse | Write,Edit | When editing a CSS/style file, injects DESIGN.md into context if present in project root. |
| `destructive-prompt-scanner` | UserPromptSubmit | (none) | Scans the user prompt for destructive patterns and injects an |
| `detect-stack` | — | — | Usage: bash detect-stack.sh [project_dir] |
| `display-secret-redactor` | MessageDisplay | (none) | Last line of defense, and the only one that protects the HUMAN rather than the |
| `economy-reinforce` | UserPromptSubmit | (none) | Re-injects active economy tier rules every Nth prompt to prevent drift. |
| `editor-config-guard` | PreToolUse | Write, Edit, MultiEdit | The `.claude/settings.json` hook-injection / `.mcp.json` stdio-server primitive |
| `elicitation-discovery` | Elicitation, ElicitationResult | * | Elicitation lets MCP servers solicit structured input from the user — a |
| `elicitation-guard` | Elicitation | * | SYNC (blocking) | MCP servers can solicit structured input from the user via Elicitation forms — |
| `enforce-pkg-manager` | PreToolUse | Bash | Detects lockfiles and blocks the wrong package manager. |
| `env-exec-guard` | PreToolUse | Bash | Setting a code-injecting environment variable causes arbitrary code execution on |
| `env-file-guard` | PreToolUse | Bash, Read | Blocks reading/editing .env files (which typically contain credentials). |
| `event-logger` | PermissionDenied | (none) | Logs to ~/.claude/supercharger/events.log (async, no output to Claude) |
| `fact-gate` | PreToolUse | Edit,Write,MultiEdit,NotebookEdit | OPT-IN, default OFF. On the FIRST edit of a given file in a session it denies |
| `failure-tracker` | PostToolUse | Bash | Detects when the same command fails repeatedly and logs the pattern. |
| `file-lease` | PreToolUse | Write,Edit,MultiEdit,NotebookEdit | Advisory guard for the concurrent-edit half of the scope-file-session-scoping |
| `file-watcher` | FileChanged | .env,.envrc,package.json,.claude/settings.json | Notifies Claude when watched files change so it doesn't act on stale assumptions. |
| `generated-file-guard` | PreToolUse | Write, Edit, MultiEdit | Editing a GENERATED/derived file instead of its source is wasted work — the edit |
| `git-config-exec-guard` | PreToolUse | Bash | the next ordinary git command into arbitrary shell execution — core.fsmonitor, |
| `git-remote-guard` | PreToolUse | Bash (git *) | git-safety.sh polices HOW you push (force, --no-verify, protected branch) but |
| `git-safety` | PreToolUse | Bash (git *) | shellcheck source=hooks/lib-suppress.sh |
| `harness-tamper-guard` | PreToolUse | Bash | Self-defense on the BASH channel. path-guard protects .claude/settings.json and |
| `human-approval-gate` | PreToolUse | Bash,PowerShell | Soft gate: pauses on high-risk commands and forces Claude to ask the user |
| `install-script-guard` | PreToolUse | Write, Edit, MultiEdit | npm/pnpm/yarn/bun run lifecycle scripts automatically on `install` |
| `lazy-refactor-check` | PostToolUse | Edit, MultiEdit | Detects when Claude renames a parameter `foo` to `_foo` instead of properly |
| `learn-from-blocks` | SessionStart | (none) | Injects accumulated learnings: blocked commands, user corrections, |
| `learn-from-prompts` | UserPromptSubmit | (none) | Detects correction AND reinforcement patterns in user prompts. |
| `lesson-recall` | UserPromptSubmit | (none) | Tokenizes user prompt, computes Jaccard overlap against stored |
| `lesson-record` | Stop | * | Scans assistant's last transcript message for diagnostic markers |
| `lockfile-integrity-guard` | PreToolUse | Write,Edit,MultiEdit,NotebookEdit | Dependency lockfiles are MACHINE-GENERATED — they encode a resolved dependency |
| `mcp-circuit-breaker` | — | — | Events: PreToolUse | mcp__   (blocks calls to a server in cooldown) |
| `mcp-destructive-guard` | PreToolUse | infrastructure / filesystem / git MCP servers | These MCP servers act through STRUCTURED tool calls, not a shell command |
| `mcp-egress-guard` | PreToolUse | mcp__ | Classifies URLs/hosts in an MCP tool's arguments and blocks the dangerous |
| `mcp-github-write-gate` | PreToolUse | mcp__github__* | Blocks destructive autonomous writes via the GitHub MCP server. Real incident: |
| `mcp-output-truncator` | PostToolUse | mcp__ | Truncates large MCP tool responses to prevent context window flooding. |
| `mcp-playwright-guard` | PreToolUse | mcp__playwright__*,mcp__puppeteer__* | Blocks browser-MCP shapes that exfiltrate or RCE. Real CVEs: |
| `mcp-provenance` | PostToolUse | mcp__ | Complements prompt-injection-scanner (which catches "ignore instructions"-style |
| `mcp-sql-guard` | PreToolUse | mcp__postgres__*,mcp__supabase__* | Blocks destructive SQL via the Postgres / Supabase MCP servers. Real incident: |
| `mcp-tracker` | PostToolUse | mcp__ | Writes the active MCP server name to a scope file for statusline display. |
| `memory-write-guard` | PreToolUse | Write,Edit | Blocks writes to AUTO-LOADED files (persistent memory AND agent-instruction files) |
| `notebook-exec-guard` | PreToolUse | NotebookEdit | A Jupyter cell executes through the kernel, not the shell — so a cell that |
| `notify-permission` | PermissionRequest | (none) | Only fires for tools not auto-approved by smart-approve. |
| `notify-stop` | Stop | * | Notifies when a turn finishes — but only for turns longer than a threshold |
| `notify` | Notification | idle_prompt | shellcheck source=hooks/lib-suppress.sh |
| `output-secrets-scanner` | PostToolUse | Bash,Read | Scans tool output for leaked secrets and warns Claude not to repeat them. |
| `package-source-guard` | PreToolUse | Write, Edit, MultiEdit | Supply-chain: flags a dependency added/changed to point at a NON-REGISTRY |
| `path-guard` | PreToolUse | Write,Edit | Hardens Write/Edit against path-based attacks: |
| `permission-denied-advisor` | PermissionDenied | (none) | Injects context when user denies a permission, so Claude stops retrying |
| `phantom-import-guard` | PostToolUse | Write, Edit, MultiEdit | Catches a hallucinated LOCAL relative import (`./services/email` when the file is |
| `plugin-config-seed` | SessionStart | # Event: SessionStart | The installer has an interactive wizard that writes role / economy-tier / |
| `plugin-settings-seed` | SessionStart | — | Closes the last automatic gap between the plugin and the classic install. |
| `post-compact-inject` | PostCompact | (none) | After context compaction, re-injects session constraints so Claude |
| `post-write-advisor` | PostToolUse | Write, Edit, MultiEdit | Folds three advisory checks that each used to be a separate PostToolUse hook — |
| `precompact-priorities` | PreCompact | (none) | Augments the default compact prompt with fidelity rules so the |
| `project-config` | SessionStart | (none) | (no description) |
| `prompt-injection-scanner` | PostToolUse | mcp__*,WebFetch,WebSearch,Read | Scans MCP and external tool outputs for prompt injection attempts. |
| `prompt-layer-inject` | SessionStart | (none) | Delivers the instructional/prompt layer under the PLUGIN runtime, where a plugin |
| `prompt-secret-guard` | UserPromptSubmit | (none) | Blocks a prompt that contains what looks like a LIVE credential BEFORE it is |
| `prompt-validator` | UserPromptSubmit | (none) | Deterministic enforcement: catches obvious anti-patterns via regex. |
| `pth-persistence-guard` | PreToolUse | Write, Edit, MultiEdit | CPython executes any line in a `.pth` file that starts with `import ` — every |
| `quality-gate` | PostToolUse | Write,Edit | Stage 1: Run linter → Stage 2: Auto-fix → Stage 3: Re-check |
| `rate-limit-advisor` | UserPromptSubmit | (none) | Flags: async | (no description) |
| `readonly-guard` | PreToolUse | Write,Edit,MultiEdit,NotebookEdit,Bash | While a read-only window is active (/sc-readonly), blocks every file edit and every |
| `redirect-clobber-guard` | PreToolUse | Bash | The Write/Edit review path is guarded (path-guard, confidence-gate, scope-guard), |
| `reentry-detector` | UserPromptSubmit | (none) | Detects when system output (hook messages, [MEM], [CTX]) gets pasted back |
| `repetition-detector` | PostToolUse | Bash,Read | Merged from loop-detector.sh + reread-detector.sh |
| `safety` | PreToolUse | Bash, PowerShell | Per-category toggles: disable specific security categories via |
| `scope-guard` | PostToolUse (check) | Write,Edit (check) | Modes: |
| `session-checkpoint` | PostToolUse | Write,Edit,Bash | Flags: async | Writes a lightweight checkpoint for crash recovery after every file change. |
| `session-complete` | Stop | (none) | Logs session metadata on exit. Sends webhook if configured. |
| `session-end` | SessionEnd | (none) | Logs session stats and cleans up transient scope files. |
| `session-memory-inject` | SessionStart | * | Injects .claude/supercharger-memory.md into context if present. |
| `session-memory-write` | Stop | * | Writes a compressed session summary to .claude/supercharger-memory.md |
| `setup-check` | Setup | (none) | Fires when Claude Code runs `--init`, `--init-only`, or `--maintenance`. |
| `shell-escape-advisor` | UserPromptSubmit | (none) | Claude Code's `! <cmd>` prompt prefix runs commands directly in the user's |
| `skill-poisoning-scanner` | PreToolUse | Skill | Scans skill content for hidden shell commands, encoded payloads, |
| `slow-tool-detector` | PostToolUse | (none) | Warns Claude when a tool takes unusually long, with tool-specific thresholds. |
| `smart-approve` | PermissionRequest | (none) | Auto-approves known-safe tool calls to reduce user prompts. |
| `standards-inject` | SessionStart | (none) | Detects project stack via lib/detect_stack.py and injects matching standards |
| `statusline` | — | — | Registered via: settings.json → statusLine → { type: "command", command: "..." } |
| `stop-failure` | StopFailure | (none) | Logs API errors (rate limits, auth failures) to errors.log for diagnosis. |
| `stop-keep-going` | Stop | (none) | Activation: opt-in only — touch ~/.claude/supercharger/scope/.keep-going |
| `stop-verify` | Stop | * | Merged from verify-on-stop.sh + project-verify.sh |
| `subagent-circuit-breaker` | SubagentStart | (none) | Tracks subagent spawns in a rolling time window per session. Warns when the |
| `subagent-cost` | SubagentStart,SubagentStop | (none) | Modes: |
| `subagent-discovery` | SubagentStart, SubagentStop | * | Subagent nesting now goes up to 5 levels deep (Claude Code v2.1.172). |
| `subagent-report-fallback` | SubagentStop | * | async | Companion to subagent-safety.sh's report-pin instruction (v2.6.82). |
| `subagent-report-notify` | SubagentStop | (none)  [BLOCKING — must inject into parent] | Closes the last gap in the report-recovery story. When a subagent's final |
| `subagent-safety` | SubagentStart | (none) | Injects safety context into sub-agents spawned via the Agent tool, |
| `subagent-stop-check` | SubagentStop | (none) | Reads last_assistant_message from subagent output and flags incomplete/failed work |
| `test-integrity-guard` | PreToolUse | Edit, MultiEdit, Write | Defends the Verification Gate ("run tests, confirm they pass"): the one way an |
| `test-mask-guard` | PreToolUse | Bash | Defends the flagship Verification Gate ("run the check, confirm it passes") at |
| `tool-call-limiter` | PreToolUse | (none) | Counts tool calls per session. Warns at 80%, blocks at cap. |
| `tool-failure-advisor` | PostToolUseFailure | (none) | Injects failure context + tool-specific hints back to Claude when any tool errors. |
| `tool-history-tracker` | PostToolUse | (none, runs on every tool) | Appends a JSONL entry per tool call to ~/.claude/supercharger/scope/.tool-history-<session_id>. |
| `tool-preferences` | PreToolUse | Bash | Reads .supercharger.json `toolPreferences` map. When Claude tries to run a |
| `trace-compactor` | PostToolUse | Bash | Compresses large Python/Node tracebacks before Claude processes them. |
| `typecheck` | PostToolUse | Write,Edit | Runs tsc --noEmit after editing .ts/.tsx files. Injects errors into context. |
| `update-check` | SessionStart | (none) | Checks for updates once per day and prints a banner if one is available. |
| `webfetch-egress-guard` | PreToolUse | WebFetch,WebSearch | The native WebFetch tool is an un-guarded network-egress channel: an indirect |
| `workflow-pwn-guard` | PreToolUse | Write, Edit, MultiEdit | A privileged workflow trigger (`pull_request_target` / `workflow_run`) runs with the |

## Standalone tools

Run any of these manually:

| Tool | Purpose |
|------|---------|
| `tools/agent-report-tail.sh` | Claude Supercharger — Agent Report Recovery |
| `tools/autopilot.sh` | Claude Supercharger — Autopilot (time-boxed auto-approve) |
| `tools/bump-version.sh` | Claude Supercharger — Version Bump Tool |
| `tools/cache-clear.sh` | Claude Supercharger — Cache Clear Tool |
| `tools/claude-check.sh` | Claude Supercharger — Installation Health Check |
| `tools/compress-memory.sh` | Claude Supercharger — Memory File Compressor |
| `tools/config-health.sh` | Claude Supercharger — Scored Installation Health Check |
| `tools/economy-switch.sh` | Resolve source directory (tools/ → repo root) |
| `tools/gen-plugin-commands.sh` | Claude Supercharger — Plugin commands/ generator |
| `tools/gen-plugin-hooks.sh` | Claude Supercharger — Plugin hooks.json generator |
| `tools/hook-doctor.sh` | Claude Supercharger — Hook Doctor |
| `tools/hook-new.sh` | Claude Supercharger — New Hook Scaffolder |
| `tools/hook-perf.sh` | Claude Supercharger — Hook Performance Profiler |
| `tools/hook-toggle.sh` | Claude Supercharger — Hook Toggle Tool |
| `tools/list-hooks.sh` | Claude Supercharger — Hook Catalog Generator |
| `tools/mcp-custom.sh` | Claude Supercharger — Custom MCP servers, profile-aware |
| `tools/mcp-profile.sh` | Claude Supercharger — MCP Profile Switcher |
| `tools/mcp-setup.sh` | set -eo pipefail |
| `tools/memory-prune.sh` | Claude Supercharger — Memory Auto-Pruner (v2.19.0) |
| `tools/notify-toggle.sh` | Claude Supercharger — Desktop Notification Toggle |
| `tools/perf-report.sh` | Claude Supercharger — Perf report (HOOK-LATENCY-PLAN Phase 3) |
| `tools/plugin-setup.sh` | Claude Supercharger — Plugin parity setup (run by a HUMAN, in a terminal) |
| `tools/profile-switch.sh` | set -euo pipefail |
| `tools/readonly.sh` | Claude Supercharger — Read-only mode (time-boxed "look, don't touch") |
| `tools/release.sh` | Claude Supercharger — Release Automation |
| `tools/sc-toggle.sh` | Claude Supercharger — Activate / Deactivate toggle |
| `tools/scope-cleanup.sh` | Claude Supercharger — Scope State Cleanup |
| `tools/session-analytics.sh` | Claude Supercharger — Session Analytics |
| `tools/strict.sh` | Claude Supercharger — Strict mode (time-boxed "ask me everything") |
| `tools/subagent-report.sh` | Claude Supercharger — Subagent Report Reader |
| `tools/supercharger.sh` | Claude Supercharger — Capability Overview |
| `tools/token-report.sh` | Claude Supercharger — Session Token Report |
| `tools/trust-mcp.sh` | Claude Supercharger — Trust an MCP server for Elicitation credential prompts |
| `tools/update.sh` | Claude Supercharger — Smart Updater |
| `tools/webhook-setup.sh` | set -eo pipefail |

---

Generated by `tools/list-hooks.sh`. Last run: see git history of this file.
