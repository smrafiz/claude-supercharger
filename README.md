# Claude Supercharger

Shell-level safety and behavioral intelligence for Claude Code.

![Version](https://img.shields.io/badge/version-2.2.0-blue) ![License](https://img.shields.io/badge/license-MIT-green) ![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux-lightgrey) ![Tests](https://img.shields.io/badge/tests-388%20passing-brightgreen)

---

Claude Code is powerful and mostly well-behaved — until it isn't. It deletes files it shouldn't, spawns agents that burn through your rate limit, or quietly re-bills you for context it already cached. One runaway session cost a reported $47K. Silent credential exposure in tool output is common enough to have a CVE. And when Claude crashes mid-session, your context is gone.

Supercharger adds 62 shell hooks that run outside Claude's process. Claude can't see them, can't reason around them, can't be prompted to skip them. If a hook exits non-zero, the command doesn't run. That's it.

Here's what it shows at the start of every session:

```
[claude-sonnet-4-6] myproject | main | TypeScript | Eco: Lean | Agent: Debugger | MCP: context7 | +156/-23
████████████░░░░░░░░ Context: 60% (120.5K/200K) | 115.2K in / 5.3K out | cache 92% (~103.7K saved)
Cost: $2.45 | Time: 8m 12s | Session: 24% (resets: 3h 42m) · Weekly: 15%
```

Model, project, branch, stack, economy tier, agent, MCP profile, context pressure, cache efficiency, cost, and rate-limit burn — at a glance, before you type a single prompt.

---

## Quick install

```bash
git clone https://github.com/smrafiz/claude-supercharger.git && cd claude-supercharger && ./install.sh
```

Takes 30 seconds. Backs up your config first. `./uninstall.sh` reverses everything.

<details>
<summary>Other install options</summary>

**One-liner** (temp clone, auto-clean):
```bash
bash -c 'TMP=$(mktemp -d) && git clone https://github.com/smrafiz/claude-supercharger.git "$TMP/cs" && "$TMP/cs/install.sh" && rm -rf "$TMP"'
```

**Non-interactive** (CI or scripts):
```bash
./install.sh --mode full --roles developer --economy lean
```

**Windows:** Use [WSL](https://learn.microsoft.com/en-us/windows/wsl/install) or Git Bash.

</details>

---

## What you get

### Protection — can't be bypassed

- **Destructive command blocking** — `rm -rf /`, `DROP TABLE`, `chmod 777`, `curl | bash`, force-push to main. Blocked at the shell level, not via Claude's judgment.
- **Code security scanning** — catches `eval()`, `.innerHTML =`, `pickle.load()`, SQL injection via string concat, `os.system()`, weak crypto, GitHub Actions injection, and hardcoded secrets in code Claude writes.
- **Credential leak detection** — scans Bash and Read output for AWS, OpenAI, Slack, Stripe, HuggingFace, GCP, Azure, SendGrid, and Twilio credentials before Claude can repeat them.
- **Prompt injection defense** — scans MCP and web tool output for "ignore previous instructions" patterns and similar attacks.
- **Smart auto-approve** — automatically approves safe read operations (`Read`, `Glob`, `Grep`, `git status`, `ls`, test runners, `curl` GET) so you're not clicking through obvious prompts all day.

### Cost control — new in v2

- **Session cost tracking** — every tool call contributes to a running total. No guessing at the end.
- **Budget cap** — set a session limit in `.supercharger.json` or `SESSION_BUDGET_CAP`. At 80% you get a warning. At 100%, non-read tools are blocked.
- **Cost forecast** — before Claude spawns a subagent, it estimates the cost based on your session average. You see `[COST] Est. ~$1.90` before it runs.
- **Per-subagent visibility** — each subagent reports on completion: `[AGENT] code-helper: ~$0.42 (28K tokens, 34s)`. Costs roll up to the session total.
- **Rate-limit burn projection** — predicts when your session will hit the rate limit and shows `~52m left at this pace`. Warns when under 30 minutes.
- **Cache health monitoring** — warns when your prompt cache hit rate drops below 50%, which means you're being silently re-billed for context you already paid for.

### Session intelligence

- **Statusline** (shown above) — three lines covering everything relevant about your current session.
- **Session memory** — writes `.claude/supercharger-memory.md` on stop and on `/compact`. Modified files, recent commits, economy tier, corrections. Injected automatically at the next session start.
- **Crash-resilient checkpoints** — state is saved after every file-modifying tool call. If Claude crashes, the next session picks up where you left off.
- **Context pressure advisor** — warns at 50%, recommends `/compact` at 70%, recommends `eco minimal` at 80%, critical at 90%. This alone has saved me from a lot of wasted context.
- **Adaptive economy** — auto-switches economy tier as context pressure rises. Learns from recent sessions — if you've been running hot, it starts conservative next time.
- **Learning loop** — blocked commands and user corrections are logged and injected at the start of every session. The more you correct it, the less you have to.

### Developer experience

- **8 roles** — `developer`, `designer`, `devops`, `pm`, `researcher`, `student`, `data`, `writer`. Switch mid-conversation with natural language: `"as developer"`.
- **9 agent types** — `architect`, `code-helper`, `data-analyst`, `debugger`, `general`, `planner`, `researcher`, `reviewer`, `writer`. Each prompt is classified and Claude gets a hint about which profile fits.
- **Token economy** — 3 tiers (`standard`, `lean`, `minimal`). Switch mid-conversation with `eco lean`. I use Lean by default. Minimal is useful for long agentic sessions where you're mostly watching Claude work.
- **Slash commands** — `/think`, `/challenge`, `/audit`, `/handoff`, `/security`, `/stuck`, `/scope`, `/pr`.
- **Skill routing** — a trigger table maps common tasks to the right Claude skill without loading the full skill index.
- **MCP server profiles** — `light`, `dev`, `research`, `full`. Switch with `bash tools/mcp-profile.sh [profile]`. Role-based additions apply on top.

---

## How it works

Two layers. They make different guarantees.

**Shell hooks** run outside the Claude process, before commands execute. Claude cannot see them, reason about them, or negotiate around them. Exit code 2 means the command doesn't run — full stop.

**Prompt-level rules** live in `CLAUDE.md` and shape behavior: economy, routing, roles, compaction. Claude follows them reliably, but not unconditionally. Think of it as a locked door versus a sign that says "please knock."

Both are useful. Neither replaces the other.

### Shell hooks vs. `/permissions`

| | `/permissions` (inside Claude) | Supercharger hooks (outside Claude) |
|---|---|---|
| Claude sees the rules | Yes | No |
| Can reason and negotiate | Yes | Can't argue with exit code 2 |
| Advisory or enforced | Advisory | Enforced |

Use both. `/permissions` for wildcard approvals. Supercharger for hard blocks.

---

## Two modes

| Mode | Hooks | What you get |
|---|---|---|
| **Safe** | 10 | The non-negotiable blocks. Destructive command blocking, credential scanning, prompt injection defense, smart auto-approve, cache health. Install and forget. |
| **Full** | 62 | Everything. Cost tracking, session memory, notifications, quality gates, context advisor, learning loop, crash recovery, statusline. For heavy Claude Code use. |

---

## Configuration

### Project config

`.supercharger.json` in your repo root, committed. Everyone on the team gets the same behavior:

```json
{"roles": ["developer", "designer"], "economy": "lean", "hints": "React + Tailwind, use pnpm"}
```

Set a budget cap here too: `"budget": 5.00`.

### Session memory

Full mode writes `.claude/supercharger-memory.md` when Claude stops and when `/compact` runs. It captures modified files, recent commits, active economy tier, and recent corrections, then injects it at the next session start automatically.

Add to `.gitignore` for local-only memory, or commit it for shared memory across the team:

```
.claude/supercharger-memory.md
```

### Project verify hook

Drop `.claude/verify.sh` in your repo and it runs when Claude stops. If it fails, Claude sees the output and keeps fixing.

```bash
cp ~/.claude/supercharger/docs/templates/verify.sh .claude/verify.sh
# uncomment the lines matching your stack
chmod +x .claude/verify.sh
```

---

## Going deeper

<details>
<summary>Safe mode — full hook details</summary>

| Hook | What it does |
|---|---|
| **safety.sh** | Blocks: `rm -rf /`, `DROP TABLE`, `chmod 777`, `curl \| bash`, force-push to main, hardcoded credentials, clipboard exfiltration, browser cookie access, shell history access |
| **code-security-scanner.sh** | Scans code Claude writes for: `eval()`, `.innerHTML =`, `pickle.load()`, SQL injection via string concat, `os.system()`, weak crypto (MD5), GitHub Actions injection, hardcoded secrets. Warns — doesn't block (patterns like `eval()` are legitimate in test files) |
| **smart-approve.sh** | Auto-approves safe read operations: `Read`, `Glob`, `Grep`, `git status`, `ls`, test runners, `curl` GET requests |
| **audit-trail.sh** | Logs every file write and shell command to JSONL. Credentials auto-redacted. 30-day rotation |
| **trace-compactor.sh** | Compresses large Python/Node tracebacks to a 1-line summary before injecting into context |
| **mcp-output-truncator.sh** | Caps MCP tool responses at 3.5K chars to prevent context flooding |
| **prompt-injection-scanner.sh** | Scans MCP/web tool outputs for "ignore previous instructions" and similar patterns |
| **output-secrets-scanner.sh** | Scans Bash/Read output for leaked credentials (AWS, OpenAI, Slack, Stripe, HuggingFace, GCP, Azure, SendGrid, Twilio). Warns Claude not to repeat them |
| **config-scan.sh** | At session start, scans project CLAUDE.md files for injection patterns. Also checks `.claude/settings.json` for non-Supercharger hooks (CVE-2025-59536 guard) |
| **cache-health.sh** | Monitors prompt cache hit rate. Warns when it drops below 50% — a sign you're being silently re-billed for full context |

</details>

<details>
<summary>Full mode — what the extra 52 hooks do</summary>

| Category | Hooks | What's added |
|---|---|---|
| **Notifications** | 5 | Desktop alerts when Claude is idle, needs input, or needs permission. Shows task summary and what's needed |
| **Git safety** | 3 | Blocks force-push, rebase on main, enforces package manager consistency (no `npm` in a pnpm project) |
| **Scope & memory** | 6 | Tracks files touched, writes session memory on stop, injects it at the next session start |
| **Learning** | 4 | Logs blocked commands and user corrections, injects them at session start so Claude doesn't repeat mistakes |
| **Monitoring** | 8 | Context pressure advisor (warns at 50%, 70%, 80%, 90%), dep vulnerability scanner, repetition/re-read detector, MCP server tracker, file change watcher |
| **Agent routing** | 3 | Classifies each prompt by task type, hints Claude which agent profile to use |
| **Session & compaction** | 4 | Backs up memory before compaction, restores it after, logs session summary on stop |
| **Verification & quality** | 3 | Warns if files were modified but no test ran, lint check after edits, TypeScript type-check after `.ts/.tsx` edits |
| **Cost shield** | 5 | Session cost tracking, budget cap with hard stop, cost forecast before agent spawns, per-subagent cost logging |
| **Smart adaptation** | 3 | Auto-switches economy tier at context thresholds, calibrates reasoning depth by task complexity, warns when rate limit projected to exhaust |
| **Session intelligence** | 1 | Crash-resilient checkpoint written on every file change, recovered automatically on next session start |

**Context advisor** — warns at 50%, recommends `/compact` at 70%, recommends `eco minimal` at 80%, critical warning at 90%.

**Verify on stop** — if files were modified in a session but no test or build command ran, you get a warning. Good for catching sessions where Claude edited something and you forgot to check.

**Quality gate** — lint after file edits (Developer role). TypeScript type-check after every `.ts`/`.tsx` edit. To opt out per project: `touch .supercharger-no-typecheck`.

**Traceback compressor** — a 50KB Python or Node stacktrace gets compressed to a 1-line summary before it hits the context window.

**Loop and re-read detection** — catches repeated identical tool calls and warns when Claude re-reads unchanged files.

**Audit trail** — every file write and shell command logged to JSONL. Credentials auto-redacted. 30-day rotation.

**Thinking budget** — nudges Claude to calibrate reasoning depth. Simple prompts get minimal thinking. Complex prompts get thorough reasoning. Advisory, not enforced — saves 20-30% thinking tokens on simple tasks.

</details>

<details>
<summary>Tools reference</summary>

All scripts live in `~/.claude/supercharger/tools/` after install:

| Script | Purpose |
|---|---|
| `update.sh` | Self-update |
| `economy-switch.sh` | Change economy tier permanently |
| `hook-toggle.sh` | Enable or disable individual hooks |
| `config-health.sh` | Installation health check |
| `mcp-setup.sh` | Add MCP servers interactively |
| `mcp-profile.sh` | Switch MCP profile |
| `claude-check.sh` | Full diagnostic |
| `token-report.sh` | Per-session token cost breakdown |
| `session-analytics.sh` | Daily cost rollup + per-project breakdown across all sessions (`--days N`) |
| `notify-toggle.sh` | Toggle desktop notifications |
| `webhook-setup.sh` | Configure webhooks |
| `supercharger.sh` | Capability overview |
| `hook-perf.sh` | Hook performance profiler — timing analysis from audit data |
| `bump-version.sh` | Version management (dev use) |

</details>

<details>
<summary>MCP server profiles</summary>

Auto-configured based on your selected role. No API keys needed for the core set.

Switch profiles with `bash tools/mcp-profile.sh [profile]`. Takes effect on the next session.

| Profile | Servers | Token overhead |
|---|---|---|
| `light` (default) | context7 | ~300 |
| `dev` | + Playwright, GitHub, Magic UI | ~1,200 |
| `research` | + Sequential Thinking, Memory | ~1,500 |
| `full` | everything | ~3,500 |

Role-based additions apply on top of the profile: Developer adds Playwright, GitHub, and Magic UI. Designer adds Magic UI.

Supercharger tags its own MCP entries with `#supercharger` and does not touch your existing servers.

</details>

<details>
<summary>Statusline — indicators and transient alerts</summary>

```
[claude-sonnet-4-6] myproject | main | TypeScript | Eco: Lean | Agent: Debugger | MCP: context7 | +156/-23
████████████░░░░░░░░ Context: 60% (120.5K/200K) | 115.2K in / 5.3K out | cache 92% (~103.7K saved)
Cost: $2.45 | Time: 8m 12s | Session: 24% (resets: 3h 42m) · Weekly: 15%
```

Line 1: model, project, git branch, detected stack, economy tier, active agent, active MCP server, lines added/removed.
Line 2: context bar, percentage, token counts in/out, cache efficiency.
Line 3: cost, duration, rate limit burn.

Transient indicators appear on line 1 when something fires:

| Indicator | Appears when | Duration |
|---|---|---|
| `Mem: Restored` | Post-compaction memory restore | 5 min |
| `⚠ Scan: Secrets` | output-secrets-scanner fires | 2 min |
| `⚠ Scan: Code` | code-security-scanner fires | 2 min |
| `⚠ Scan: Injection` | prompt-injection-scanner fires | 2 min |

</details>

<details>
<summary>Slash commands and skill routing</summary>

### Slash commands

| Command | Purpose |
|---|---|
| `/think [problem]` | Structured reasoning for ambiguous problems |
| `/challenge [decision]` | Adversarial stress-test — finds flaws, not confirmation |
| `/audit [scope]` | Consistency sweep across a codebase scope |
| `/handoff [context]` | Structured session resume brief — written to `.claude/handoff.md` |
| `/security [scope]` | OWASP-anchored security review with severity-ranked findings |
| `/stuck [symptom]` | Breaks debug loops — catalogs attempts, generates fresh hypotheses |
| `/scope [task]` | Pre-flight check — files to touch, risks, approval gate |
| `/pr [description]` | Prepare and create a pull request in one step |

### Skill routing

A trigger table in `CLAUDE.md` maps common tasks to the right Claude skill without loading the full skill index:

| Task | Skill |
|---|---|
| Debugging / errors | `superpowers:systematic-debugging` |
| TDD / new feature | `superpowers:test-driven-development` |
| Multi-step plan | `superpowers:writing-plans` |
| Execute a plan | `superpowers:executing-plans` |
| Code review | `superpowers:requesting-code-review` |
| Branch complete | `superpowers:finishing-a-development-branch` |

</details>

---

## FAQ

<details>
<summary>Will this break my existing Claude setup?</summary>

No. The installer backs up your config first. `./uninstall.sh` restores exactly what you had.
</details>

<details>
<summary>A hook blocked something I need.</summary>

`bash tools/hook-toggle.sh safety off` — or run the command directly in your terminal, outside Claude.
</details>

<details>
<summary>How do I see what hooks are outputting?</summary>

Hook output is hidden from the UI by default. To re-enable visibility:

- **Global:** `touch ~/.claude/supercharger/scope/.debug-hooks`
- **Project-only:** `touch .supercharger-debug` in the project root

Remove the file to suppress again.
</details>

<details>
<summary>How do I upgrade?</summary>

`bash ~/.claude/supercharger/tools/update.sh`
</details>

<details>
<summary>Does this touch my existing MCP servers?</summary>

No. Supercharger tags its entries with `#supercharger`. Your existing servers are not modified.
</details>

<details>
<summary>How much context overhead does it add?</summary>

~300–3,500 tokens per session, depending on MCP profile. Switch with `bash tools/mcp-profile.sh light` for the minimum.
</details>

<details>
<summary>The statusline shows wrong values.</summary>

Run `bash ~/.claude/supercharger/tools/config-health.sh` to check the installation, then `bash ~/.claude/supercharger/tools/claude-check.sh` for a full diagnostic.
</details>

<details>
<summary>How much does it cost?</summary>

Nothing. No API keys, no external calls, no telemetry. Everything runs locally.
</details>

---

## Requirements

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI
- Bash 3.2+ (macOS or Linux)
- Python 3 (ships with macOS)
- **Windows:** [WSL](https://learn.microsoft.com/en-us/windows/wsl/install) or Git Bash

---

## Credits

Built on patterns from [SuperClaude](https://github.com/SuperClaude-Org/SuperClaude_Framework), [agent-guardrails-template](https://github.com/TheArchitectit/agent-guardrails-template), [Trail of Bits claude-code-config](https://github.com/trailofbits/claude-code-config), [claude-code-quality-hook](https://github.com/dhofheinz/claude-code-quality-hook), [prompt-master](https://github.com/nidhinjs/prompt-master), [oh-my-claudecode](https://github.com/Yeachan-Heo/oh-my-claudecode), [get-shit-done](https://github.com/gsd-build/get-shit-done), [claude-code-system-prompts](https://github.com/Piebald-AI/claude-code-system-prompts), [claude-code-tips](https://github.com/ykdojo/claude-code-tips), [claude-code-warp](https://github.com/warpdotdev/claude-code-warp), [claude-guard](https://github.com/derek-larson14/claude-guard), [token-optimizer](https://github.com/alexgreensh/token-optimizer), [CCNotify](https://github.com/dazuiba/CCNotify).

## License

MIT — see [LICENSE](LICENSE)
