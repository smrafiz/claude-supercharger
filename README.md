# Claude Supercharger

Runtime safety and intelligence for Claude Code. Shell hooks Claude can't see, can't reason around, can't talk its way past.

![Version](https://img.shields.io/badge/version-1.0.0-blue) ![License](https://img.shields.io/badge/license-MIT-green) ![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux-lightgrey) ![Tests](https://img.shields.io/badge/tests-778%20passing-brightgreen)

```
[claude-sonnet-4-6] myproject | main | TypeScript | Eco: Lean | Agent: Debugger | MCP: context7 | +156/-23
████████████░░░░░░░░ Context: 60% (120.5K/200K) | 115.2K in / 5.3K out | cache 92% (~103.7K saved)
Cost: $2.45 | Time: 8m 12s | Session: 24% (resets: 3h 42m) · Weekly: 15%
```

```bash
git clone https://github.com/smrafiz/claude-supercharger.git && cd claude-supercharger && ./install.sh
```

30 seconds. Backs up your config. `./uninstall.sh` reverses everything.

---

## How it works

Two layers with different guarantees.

**Shell hooks run outside Claude's process, before commands execute.** Claude can't see them, can't reason about them, can't be prompted to skip them. Exit code 2 means the command doesn't run.

**Prompt rules in `CLAUDE.md` shape behavior** — economy tier, role, routing. Claude follows them reliably, but not unconditionally.

```
You ──▶ Claude ──▶ Tool call ──▶ [Hook] ──▶ exit 0 or exit 2
                                    │
                                    ▼
                          Runs outside Claude's view
```

|  | `/permissions` (inside Claude) | Supercharger hooks (outside Claude) |
|---|---|---|
| Claude sees the rules | Yes | No |
| Can negotiate | Yes | Can't argue with exit code 2 |
| Advisory or enforced | Advisory | Enforced |

Use both. `/permissions` for wildcard approvals. Supercharger for hard blocks.

**This is the difference** between supercharger and prompt-only frameworks. SuperClaude's confidence-check, agent-os standards, BMad modes — all are markdown files Claude reads and chooses to follow. Supercharger ships real shell hooks that run regardless.

---

## What you get

### Runtime enforcement (can't be bypassed)

- **Destructive command blocking** — `rm -rf /`, `DROP TABLE`, `chmod 777`, `curl | bash`, force-push to main
- **Confidence gate** — gates Edit/Write/destructive-Bash on a real score (recent failures, read-before-write, repetition). At low confidence: warns or denies via PreToolUse permission decision
- **Code security scanning** — `eval()`, `pickle.load()`, SQL injection, weak crypto, hardcoded secrets, GitHub Actions injection
- **Credential leak detection** — scans Bash/Read output for AWS, OpenAI, Slack, Stripe, GCP, Azure tokens before Claude can repeat them
- **Prompt injection defense** — scans MCP and web tool output for injection patterns
- **Smart auto-approve** — read-only tools (`Read`, `Glob`, `Grep`, `git status`, test runners) bypass the prompt automatically

### Cost control

- **Session cost tracking** — every tool call rolls up. No surprises at the end
- **Budget cap** — set `"budget": 5.00` in `.supercharger.json`. Warns at 80%, blocks non-read tools at 100%
- **Cost forecast** — `[COST] Est. ~$1.90` before subagents spawn
- **Rate-limit burn projection** — `~52m left at this pace`
- **Cache health monitoring** — warns when cache hit rate drops below 50% (you're being silently re-billed)

### Memory across sessions

- **Reflexion memory** — at end-of-turn, scans for diagnostic markers (`the issue was`, `root cause`, `fixed by`) and appends a structured lesson record. On the next prompt, surfaces matching past lessons via Jaccard overlap. Per-project, no cross-pollination.
- **Stack-derived standards** — detects React, Next.js, Vue, Svelte, Python, Go, Rust, PHP at session start and injects forbidden patterns + toolchain conventions + pitfalls. Tier-scaled (15–400 tokens).
- **Session memory** — modified files, recent commits, economy tier, corrections injected at next session start
- **Crash-resilient checkpoints** — state saved after every file modification

### Developer experience

- **Statusline** — model, project, branch, stack, tier, agent, MCP profile, context bar, cache efficiency, cost, rate-limit burn — every line
- **8 roles** — `developer`, `designer`, `devops`, `pm`, `researcher`, `student`, `data`, `writer`. Switch with `as developer`
- **Token economy** — 3 tiers (`standard`, `lean`, `minimal`). Switch with `eco lean`
- **9 agent types** — every prompt classified, Claude gets a routing hint
- **Slash commands** — `/think`, `/challenge`, `/audit`, `/security`, `/stuck`, `/scope`, `/pr`, `/handoff`, `/devlog`, `/design`, `/multi-review`, `/reflect`, `/perf`, `/profile`, `/supercharger`
- **MCP profiles** — `light` (300 tokens), `dev` (1,200), `research` (1,500), `full` (3,500)

---

## Install modes

| Mode | Hooks | Use when |
|---|---|---|
| **Safe** | 16 | Non-negotiable security blocks only. Install and forget. |
| **Full** | 78 | Everything. Cost tracking, memory, learning loop, statusline, confidence gate. Recommended. |

```bash
./install.sh                                    # interactive
./install.sh --mode full --roles developer      # non-interactive
```

`uninstall.sh` reverses everything from a backup.

---

## Configure

### Project-level

`.supercharger.json` in your repo root:

```json
{
  "roles": ["developer", "designer"],
  "economy": "lean",
  "budget": 5.00,
  "profile": "fast",
  "hints": "React + Tailwind, use pnpm"
}
```

### Performance profile

| Profile | Behavior |
|---|---|
| `standard` | All hooks active (default) |
| `fast` | Skips 8 analytics hooks; keeps code-quality |
| `minimal` | Skips 11 hooks; security-only |

Security hooks always run regardless of profile.

```bash
SUPERCHARGER_PROFILE=fast claude
# or per-project: {"profile": "fast"}
```

### Disable categories

```json
{"disableSecurityCategories": ["clipboard", "history"]}
```

Categories: `filesystem`, `database`, `destructive`, `network`, `credentials`, `persistence`, `clipboard`, `browser`, `history`, `selfmod`.

### Disable individual features

| Feature | Env var |
|---|---|
| Reflexion memory | `SUPERCHARGER_LESSONS=0` |
| Stack standards | `SUPERCHARGER_STANDARDS=0` |
| Confidence gate | `SUPERCHARGER_CONFIDENCE=0` |
| Memory injection | `SUPERCHARGER_NO_MEMORY=1` |

### Project verify hook

Drop `.claude/verify.sh` in your repo. Claude runs it on stop; failures keep it fixing.

```bash
cp ~/.claude/supercharger/docs/templates/verify.sh .claude/verify.sh
chmod +x .claude/verify.sh
```

---

## Going deeper

- **All 78 hooks documented:** [`docs/HOOKS.md`](./docs/HOOKS.md) — event, matcher, purpose
- **Hook authoring guide:** [`docs/HOOK_AUTHORING.md`](./docs/HOOK_AUTHORING.md) — write your own
- **Roadmap:** [`docs/ROADMAP.md`](./docs/ROADMAP.md)

<details>
<summary>Statusline indicators</summary>

```
[claude-sonnet-4-6] myproject | main | TypeScript | Eco: Lean | Agent: Debugger | MCP: context7 | +156/-23
████████████░░░░░░░░ Context: 60% (120.5K/200K) | 115.2K in / 5.3K out | cache 92% (~103.7K saved)
Cost: $2.45 | Time: 8m 12s | Session: 24% (resets: 3h 42m) · Weekly: 15%
```

Line 1: model, project, git branch, detected stack, economy tier, active agent, active MCP, lines added/removed.
Line 2: context bar, percentage, token counts, cache efficiency.
Line 3: cost, duration, rate limit burn.

Transient alerts on line 1: `Mem: Restored`, `⚠ Scan: Secrets`, `⚠ Scan: Code`, `⚠ Scan: Injection`.
</details>

<details>
<summary>Slash commands</summary>

| Command | Purpose |
|---|---|
| `/think [problem]` | Structured reasoning for ambiguous problems |
| `/challenge [decision]` | Adversarial stress-test |
| `/audit [scope]` | Consistency sweep across a codebase scope |
| `/handoff [context]` | Session resume brief → `.claude/handoff.md` |
| `/security [scope]` | OWASP-anchored review with severity-ranked findings |
| `/stuck [symptom]` | Breaks debug loops with fresh hypotheses |
| `/scope [task]` | Pre-flight check — files to touch, risks |
| `/pr [description]` | Prepare and create a pull request |
| `/interview [topic]` | Structured requirements gathering |
| `/devlog [entry]` | Append decision to `DEV-LOG.md` |
| `/design [brand]` | Generate `DESIGN.md` — color tokens, typography, components |
| `/multi-review [target]` | Three parallel agents (security/perf/DX), synthesized |
| `/reflect` | Score session quality, write to `.claude/session-observations.md` |
| `/perf [--slow]` | Hook timing report |
| `/profile [name]` | Show or switch performance profile |
| `/supercharger` | List all slash commands |
</details>

<details>
<summary>Tools</summary>

All in `~/.claude/supercharger/tools/` after install:

| Script | Purpose |
|---|---|
| `update.sh` | Self-update |
| `economy-switch.sh` | Change economy tier permanently |
| `hook-toggle.sh` | Enable/disable individual hooks |
| `hook-new.sh` | Scaffold a new hook |
| `mcp-profile.sh` | Switch MCP profile |
| `claude-check.sh` | Full diagnostic |
| `token-report.sh` | Per-session token cost breakdown |
| `session-analytics.sh` | Daily cost rollup (`--days N`) |
| `hook-perf.sh` | Hook timing analysis |
| `hook-doctor.sh` | Diagnose broken hook installs |
</details>

<details>
<summary>MCP profiles</summary>

| Profile | Servers | Tokens |
|---|---|---|
| `light` (default) | context7 | ~300 |
| `dev` | + Magic UI | ~1,200 |
| `research` | + Sequential Thinking, Memory | ~1,500 |
| `full` | + everything (Playwright, GitHub) | ~3,500 |

Heavy/specialty servers are opt-in via `SUPERCHARGER_MCP_EXTRAS="playwright,github"`.

Switch profiles: `bash tools/mcp-profile.sh [profile]`. Supercharger tags its entries with `#supercharger` and never touches your existing servers.
</details>

---

## FAQ

<details>
<summary>Will this break my existing Claude setup?</summary>
No. The installer backs up everything. `./uninstall.sh` restores exactly what you had.
</details>

<details>
<summary>A hook blocked something I need.</summary>

`bash tools/hook-toggle.sh <hook-name> off` — or run the command directly in your terminal, outside Claude.
</details>

<details>
<summary>How do I see what hooks are outputting?</summary>

Hook output is hidden by default. To debug:
- Global: `touch ~/.claude/supercharger/scope/.debug-hooks`
- Project-only: `touch .supercharger-debug` in the project root
</details>

<details>
<summary>How do I upgrade?</summary>

`bash ~/.claude/supercharger/tools/update.sh`
</details>

<details>
<summary>Does this touch my existing MCP servers?</summary>

No. Tagged entries with `#supercharger`. Yours are not modified.
</details>

<details>
<summary>How much does it cost?</summary>

Nothing. No API keys, no external calls, no telemetry. Everything runs locally.
</details>

<details>
<summary>Can I write my own hooks?</summary>

```bash
bash ~/.claude/supercharger/tools/hook-new.sh my-hook PostToolUse Bash
bash ~/.claude/supercharger/tools/hook-toggle.sh my-hook on
```

Full guide: `docs/HOOK_AUTHORING.md`.
</details>

---

## Requirements

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI
- Bash 3.2+ (macOS or Linux)
- Python 3
- Windows: [WSL](https://learn.microsoft.com/en-us/windows/wsl/install) or Git Bash

---

## Credits

Built on patterns from [SuperClaude](https://github.com/SuperClaude-Org/SuperClaude_Framework), [agent-guardrails-template](https://github.com/TheArchitectit/agent-guardrails-template), [Trail of Bits claude-code-config](https://github.com/trailofbits/claude-code-config), [claude-code-quality-hook](https://github.com/dhofheinz/claude-code-quality-hook), [prompt-master](https://github.com/nidhinjs/prompt-master), [oh-my-claudecode](https://github.com/Yeachan-Heo/oh-my-claudecode), [get-shit-done](https://github.com/gsd-build/get-shit-done), [claude-code-system-prompts](https://github.com/Piebald-AI/claude-code-system-prompts), [claude-code-tips](https://github.com/ykdojo/claude-code-tips), [claude-code-warp](https://github.com/warpdotdev/claude-code-warp), [claude-guard](https://github.com/derek-larson14/claude-guard), [token-optimizer](https://github.com/alexgreensh/token-optimizer), [CCNotify](https://github.com/dazuiba/CCNotify), [awesome-claude-design](https://github.com/VoltAgent/awesome-claude-design), [awesome-llm-apps](https://github.com/Shubhamsaboo/awesome-llm-apps).

## License

MIT — see [LICENSE](LICENSE)
