# Claude Supercharger

Shell-level guardrails and behavioral intelligence for Claude Code.

![Version](https://img.shields.io/badge/version-1.0.0-blue) ![License](https://img.shields.io/badge/license-MIT-green) ![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux-lightgrey) ![Tests](https://img.shields.io/badge/tests-259%20passing-brightgreen)

---

## Quick install

```bash
git clone https://github.com/smrafiz/claude-supercharger.git && cd claude-supercharger && ./install.sh
```

Interactive. Two modes, a few questions, done. `./uninstall.sh` reverses everything.

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

## What it is

Supercharger has two distinct layers. They work differently and make different guarantees.

**Protection layer — shell hooks.** These run outside the Claude process, before commands execute. Claude cannot see them, cannot reason about them, and cannot argue its way around them. If a hook exits with a non-zero code, the command doesn't run. Full stop.

**Intelligence layer — prompt-level rules.** These live in `CLAUDE.md` and shape how Claude behaves: token economy, agent routing, roles, compaction strategy. They work well in practice, but Claude could technically ignore them. Think of it as the difference between a locked door and a sign that says "please knock."

Both layers are useful. Neither replaces the other.

---

## Protection layer

### Why shell hooks, not `/permissions`

Claude's built-in `/permissions` run inside the conversation — Claude sees the rules and can reason around them. Shell hooks run at the OS level. Claude never sees them.

| `/permissions` (inside Claude) | Supercharger hooks (outside Claude) |
|---|---|
| Claude sees the rules | Claude never sees them |
| Can reason and negotiate | Can't argue with exit code 2 |
| Advisory — Claude decides | Enforced — shell decides |

Use both. `/permissions` for convenience (wildcard approvals). Supercharger for hard blocks.

### Safe mode — 9 hooks

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

### Full mode adds 43 more hooks

Organized into categories:

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

---

## Intelligence layer

Everything here runs as prompt-level instructions. Claude follows them reliably, but they are advisory — not enforced.

### Statusline

Three lines shown in the terminal at the start of each Claude session:

```
[claude-sonnet-4-6] myproject | main | TypeScript | Eco: Lean | Agent: Debugger | MCP: context7 | +156/-23
████████████░░░░░░░░ Context: 60% (120.5K/200K) | 115.2K in / 5.3K out | cache 92% (~103.7K saved)
Cost: $2.45 | Time: 8m 12s | Session: 24% (resets: 3h 42m) · Weekly: 15%
```

**Line 1:** model, project name, git branch, detected stack, economy tier, active agent, active MCP server, lines added/removed

**Line 2:** context bar, context %, token counts in/out, cache efficiency

**Line 3:** session cost, duration, rate limit usage (Pro/Max subscribers)

Transient indicators that appear on line 1:

| Indicator | Appears when | Duration |
|---|---|---|
| `Mem: Restored` | Post-compaction memory restore | 5 min |
| `⚠ Scan: Secrets` | output-secrets-scanner fires | 2 min |
| `⚠ Scan: Code` | code-security-scanner fires | 2 min |
| `⚠ Scan: Injection` | prompt-injection-scanner fires | 2 min |

### Token economy

Switch mid-conversation with `eco standard`, `eco lean`, or `eco minimal`:

| Tier | Reduction | Style |
|---|---|---|
| **Standard** | ~30% | Complete sentences, explanations included |
| **Lean** | ~45% | Fragments OK, no narration |
| **Minimal** | ~60% | Telegraphic, bare deliverables only |

### Agent routing

9 agent types: `architect`, `code-helper`, `data-analyst`, `debugger`, `general`, `planner`, `researcher`, `reviewer`, `writer`.

Each prompt is classified by task type. Claude gets a hint about which agent profile fits — not a forced dispatch. It decides whether spawning a sub-agent is worth it.

Project agents take priority. Drop `.claude/agents/my-agent.md` in your repo and Supercharger tells Claude to prefer it over global agent definitions.

### Roles

8 behavioral profiles. Switch mid-conversation:

`"as developer"` · `"as designer"` · `"as devops"` · `"as pm"` · `"as researcher"` · `"as student"` · `"as data"` · `"as writer"`

### Slash commands

| Command | Purpose |
|---|---|
| `/think [problem]` | Structured reasoning |
| `/challenge [decision]` | Adversarial stress-test of a decision |
| `/refactor [file]` | Code quality sweep |
| `/audit [scope]` | Consistency sweep |
| `/test [target]` | Generate unit tests |
| `/doc [target]` | Generate documentation |

### Skill routing

A trigger table in `CLAUDE.md` routes common tasks to the right Claude skill without loading the full skill index:

| Task | Skill |
|---|---|
| Debugging / errors | `superpowers:systematic-debugging` |
| TDD / new feature | `superpowers:test-driven-development` |
| Multi-step plan | `superpowers:writing-plans` |
| Execute a plan | `superpowers:executing-plans` |
| Code review | `superpowers:requesting-code-review` |
| Branch complete | `superpowers:finishing-a-development-branch` |

---

## Install modes

| Mode | Hooks | Best for |
|---|---|---|
| **Safe** | 9 | Anyone who wants hard safety blocks with minimal overhead |
| **Full** | 52 | Anyone using Claude Code heavily who also wants the statusline, notifications, session memory, and quality gates |

Start with Safe. Add Full when you want more.

---

## Configuration

### Project config

Drop `.supercharger.json` in your repo root and commit it. Everyone on the team gets the same behavior:

```json
{"roles": ["developer", "designer"], "economy": "lean", "hints": "React + Tailwind, use pnpm"}
```

### Session memory

Full mode writes `.claude/supercharger-memory.md` when Claude stops and when `/compact` runs. It captures modified files, recent commits, active economy tier, and recent corrections. On the next session start, it gets injected automatically.

Add to `.gitignore` if the memory is local to you:

```
.claude/supercharger-memory.md
```

Or commit it for shared team memory that persists across sessions.

### Project verify hook

Drop `.claude/verify.sh` in your repo. It runs when Claude stops. If it fails, Claude sees the output and continues fixing.

```bash
cp ~/.claude/supercharger/docs/templates/verify.sh .claude/verify.sh
# uncomment the lines matching your stack
chmod +x .claude/verify.sh
```

---

## Tools

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
| `notify-toggle.sh` | Toggle desktop notifications |
| `webhook-setup.sh` | Configure webhooks |
| `supercharger.sh` | Capability overview |
| `bump-version.sh` | Version management (dev use) |

---

## MCP servers

Auto-configured based on your selected role. No API keys needed for the core set.

Switch profiles with `bash tools/mcp-profile.sh [profile]`. Takes effect on the next session.

| Profile | Servers | Token overhead |
|---|---|---|
| `light` (default) | context7 | ~300 |
| `dev` | + Playwright, GitHub, Magic UI | ~1,200 |
| `research` | + Sequential Thinking, Memory | ~1,500 |
| `full` | everything | ~3,500 |

Role-based additions apply on top of the profile: Developer adds Playwright, GitHub, and Magic UI. Designer adds Magic UI.

---

## Full mode — feature details

**Context advisor** — warns at 50% context, recommends `/compact` at 70%, recommends `eco minimal` at 80%, critical warning at 90%.

**Verify on stop** — if files were modified in a session but no test or build command ran, shows a warning.

**Quality gate** — lint check after file edits (Developer role). TypeScript type-check after every `.ts`/`.tsx` edit. Opt out per project: `touch .supercharger-no-typecheck`.

**Learning loop** — blocked commands and user corrections are logged and injected at the start of every session. The more you use it, the fewer mistakes Claude repeats.

**Traceback compressor** — 50KB Python or Node stacktrace compressed to a 1-line summary before it hits the context window.

**Loop and re-read detection** — catches repeated identical tool calls and warns when Claude re-reads unchanged files, nudging it to use cached knowledge instead.

**Audit trail** — every file write and shell command logged to JSONL. Credentials auto-redacted. 30-day rotation.

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
