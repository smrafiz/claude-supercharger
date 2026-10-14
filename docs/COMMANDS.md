# Slash commands and tools

[Back to README](../README.md)

Commands that change state or settings (`/sc`, the time-boxed modes, `/sc-update`, `/sc-pr`, `/sc-cleanup` and similar) run only when you type them. Claude cannot invoke them on its own.

On the plugin channel, commands are namespaced: `/sc-audit` becomes `/supercharger:audit`. See [INSTALL.md](INSTALL.md#install-as-a-plugin).

## Control and modes

| Command | Purpose |
|--|--|
| `/sc-autopilot 2h` | Stop the yes/no permission prompts for a set time. The safety floor stays on |
| `/sc-readonly 20m` | Block all edits and mutating shell commands; allow reads, searches and planning |
| `/sc-strict 30m` | Confirm every call. Auto-approves nothing and overrides autopilot while active |
| `/sc off\|on\|status` | Switch to plain Claude Code and back. Guards, statusline, prompt rules and Supercharger's MCP servers all stand down; nothing is uninstalled |
| `/sc-status` | What is active now: session cost, economy tier, disabled hooks, per-subagent spend |
| `/sc-profile [fast\|minimal]` | Show or switch the performance profile (skips analytics hooks to cut overhead) |
| `/sc-update` | Check for and apply Supercharger updates (classic install; the plugin uses `/plugin update`) |
| `/sc-mcp-audit [--accept] [--server NAME]` | Scan every MCP server's tool descriptions for hidden instructions (tool poisoning) and report tools whose description changed since you accepted it (rug pull). Hooks never see descriptions, so this is the only check on them |
| `/sc-notifier [install\|status\|remove]` | macOS: install, check or remove the optional notifier app |
| `/sc-doctor` | Diagnose the install: registration, deployed-code integrity, state permissions, update status. Ends with one line to paste when asking for help |

The time-boxed modes expire on their own. They are per session by default (`global` is opt-in), capped at 2h, shown in the statusline, and need no daemon. When two modes conflict, the tighter one wins: `/sc-readonly` and `/sc-strict` override `/sc-autopilot`. Autopilot only removes approval prompts; `rm -rf`, force-push and credential leaks are still blocked.

## Workflow

| Command | Purpose |
|--|--|
| `/sc-handoff [--deep] [context]` | Write a session resume brief to `.claude/handoff-<session>.md`, loaded automatically next session |
| `/sc-pr [description]` | Prepare and create a pull request |
| `/sc-scope [task]` | Pre-flight check: files to touch, risks, blast radius |
| `/sc-estimate [task]` | Time and complexity report. Stops before any code is written |
| `/sc-interview [topic]` | Structured requirements gathering, one question at a time |
| `/sc-multi-review [quick\|standard\|deep] [target]` | Parallel specialist reviewers, then a separate pass that tries to refute each finding |
| `/sc-security [scope]` | OWASP-anchored review with severity-ranked findings |
| `/sc-audit [scope]` | Consistency sweep across naming, patterns, docs and interfaces |
| `/sc-cleanup [scope]` | Dead code and unused-import removal with two-tier safety |
| `/sc-resolve-conflicts [context]` | Resolve an in-progress merge or rebase conflict, then verify it with the typecheck and tests |

## Reasoning and debugging

| Command | Purpose |
|--|--|
| `/sc-think [problem]` | Structured reasoning for ambiguous problems |
| `/sc-challenge [decision]` | Adversarial stress-test: assumptions, failure modes, strongest alternative |
| `/sc-stuck [symptom]` | Break a debugging loop with fresh hypotheses |
| `/sc-why [hook]` | Explain the most recent hook firing: what triggered, what was blocked, how to get past it |

## Insight, memory and housekeeping

| Command | Purpose |
|--|--|
| `/sc-learn <rule>` | Record an explicit project rule. Shown on every prompt in this project |
| `/sc-memory-prune` | Archive resolved memory entries so they stop loading into context |
| `/sc-perf [--slow]` | Hook timing report (see [PERFORMANCE.md](PERFORMANCE.md) for its bash 3.2 caveat) |
| `/sc-cache-stats`, `/sc-cache-clear` | Typecheck and quality-gate cache state, or clear the hash caches |
| `/sc-trust-mcp <server>` | Trust an MCP server to request credential-style fields (elicitation) and to receive credentials as tool arguments |
| `/sc-reflect` | Evidence-based retrospective; keeps only grounded, checkable lessons in `.claude/session-observations.md` |
| `/sc-devlog [entry]` | Append a decision to `DEV-LOG.md` |
| `/sc-design [brand]` | Generate `DESIGN.md`: tokens read from the project's theme, typography, components |
| `/sc-design-review [pages]` | Review UI: WCAG 2.2 AA with measured values, hierarchy, responsiveness (read-only) |
| `/supercharger` | List all slash commands |

## Bundled tools

All in `~/.claude/supercharger/tools/` after install:

| Script | Purpose |
|--|--|
| `update.sh` | Self-update |
| `claude-check.sh` | Full diagnostic (also installed as `~/.claude/claude-check.sh`) |
| `hook-toggle.sh` | Enable or disable individual hooks |
| `hook-new.sh` | Scaffold a custom hook |
| `hook-doctor.sh` | Diagnose broken hook installs |
| `economy-switch.sh` | Change the economy tier permanently |
| `mcp-profile.sh` | Switch MCP profile |
| `token-report.sh` | Per-session token cost breakdown |
| `session-analytics.sh` | Daily cost rollup (`--days N`) |
| `hook-perf.sh` | Hook timing analysis |
| `notify-toggle.sh` | Turn desktop notifications `off`, to `sound` only, or back `on` |
