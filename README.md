# Claude Supercharger

Shell-level guardrails for Claude Code. Install once, forget forever.

Claude Code has root access to your filesystem and git history. Supercharger adds enforced safety hooks, smart auto-approve, desktop notifications, and self-teaching — so you stop worrying and start shipping.

![Version](https://img.shields.io/badge/version-3.5.9-blue) ![License](https://img.shields.io/badge/license-MIT-green) ![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux-lightgrey) ![Tests](https://img.shields.io/badge/tests-255%20passing-brightgreen)

```bash
git clone https://github.com/smrafiz/claude-supercharger.git && cd claude-supercharger && ./install.sh
```

Two modes. A few questions. Done. `./uninstall.sh` reverses everything.

## What you get

- **Shell-level blocks** — dangerous commands are killed before they run. Claude can't argue, negotiate, or charm its way past an exit code.
- **Auto-approve safe ops** — `Read`, `Glob`, `Grep`, `git status`, `ls`, `cat`, test runners, `curl` GET requests. Approved once, never asked again.
- **Desktop notifications** — task complete, input needed, permission required. You stay in flow.
- **Self-teaching** — Claude learns from corrections, blocked commands, and repeated failures. Gets smarter every session.
- **4-layer injection defense** — config scan, code scan, runtime scan, secret scan. Catches prompt injection before it lands.
- **Status bar** — model, project, branch, stack, cost, token usage, cache savings, rate limit countdown. One glance tells you everything.

## Two install modes

| Mode | Hooks | What you get |
|---|---|---|
| **Safe** | 8 | Command blocking, code security scanner, auto-approve, audit trail, traceback compression, injection scanning, secret scanning, config scan |
| **Full** | 30 | Everything above + git safety, agent routing, context advisor, quality gate, notifications, scope alerts, self-teaching, verify-on-stop, failure tracking, loop/re-read detection, MCP tracking |

Safe mode is enough for most people. Full mode adds workflow features for daily Claude Code users.

---

<details>
<summary>Other install options</summary>

**One-liner** (temp clone, auto-clean):
```bash
bash -c 'TMP=$(mktemp -d) && git clone https://github.com/smrafiz/claude-supercharger.git "$TMP/cs" && "$TMP/cs/install.sh" && rm -rf "$TMP"'
```

**Non-interactive** (CI/scripts):
```bash
./install.sh --mode full --roles developer --economy lean --config deploy --settings deploy
```

**Windows:** Use [WSL](https://learn.microsoft.com/en-us/windows/wsl/install) or Git Bash.

</details>

<details>
<summary>What gets blocked — full table</summary>

Shell hooks run before commands execute. The blocks are exhaustive:

| Blocked | Why |
|---|---|
| `rm -rf /`, `rm -rf ~`, `DROP TABLE`, `chmod 777`, fork bombs | Irreversible destruction |
| `git push --force` to main/master | Overwrites shared history |
| `git reset --hard`, `git checkout .`, `git clean -f` | Loses uncommitted work |
| `curl \| bash`, `eval`, credential patterns (AWS, GitHub, Stripe, JWTs) | Remote code execution, secret exposure |
| Wrong package manager (`npm` in a pnpm project) | Corrupts lockfile |
| Writing to `.bashrc`, `.zshrc`, SSH key operations | Unauthorized persistence |
| `pbpaste`, `pbcopy`, `xclip`, clipboard commands | Clipboard exfiltration |
| Browser cookies/passwords, keychains, 1Password, `.password-store` | Credential theft |
| `.bash_history`, `.zsh_history`, shell history files | May contain secrets |

</details>

<details>
<summary>Auto-approve — what gets a free pass</summary>

No more clicking "approve" 50 times per session. These are approved with permanent session rules — approved once, never asked again:

`Read` · `Glob` · `Grep` · `git status` · `ls` · `cat` · test runners · `curl` GET requests

</details>

<details>
<summary>Token economy — tiers and switching</summary>

Three tiers, switchable mid-conversation:

| Tier | Style |
|---|---|
| **Standard** | Complete sentences. Explanations included. |
| **Lean** *(default)* | Every word earns its place. Fragments OK. |
| **Minimal** | Telegraphic. Bare output only. |

Switch mid-conversation: `eco lean` / `eco standard` / `eco minimal`

To change permanently: `bash tools/economy-switch.sh [standard|lean|minimal]`

</details>

<details>
<summary>Agent routing — how task classification works</summary>

Each prompt is classified by task type. Claude gets a hint — not a forced dispatch:

```
"null pointer at line 42"           → debugging task
"review this for security issues"   → review task
"add a login form"                  → engineering task
"write a README"                    → writing task
"compare Redis vs Memcached"        → research task
"design the auth system"            → architecture task
```

Nine agent files with scoped rules, verification checklists, and gotchas. Claude decides when a sub-agent is worth spawning.

**Project agents take priority.** Drop `.claude/agents/my-agent.md` in your repo. Supercharger tells Claude to prefer project-specific agents over global ones.

</details>

<details>
<summary>Status bar — what each field means</summary>

```
[Opus] myproject | main | TypeScript | Tony Stark | MCP: context7 | +156/-23
████████████░░░░░░░░ 60% (120.5K/200K) | 115.2K in / 5.3K out | $2.45 | 8m 12s | cache 92% (~103.7K saved) | 5h:24% (3h42m) 7d:15%
```

Line 1: model, project, branch, stack, agent, active MCP, lines added/removed.

Line 2: context bar with exact used/max tokens, in/out breakdown, cost, duration, cache with savings, 5h/7d rate limit usage with reset countdown.

Session-scoped — multiple Claude instances don't interfere.

</details>

<details>
<summary>Desktop notifications — when they fire</summary>

| When | Shows |
|---|---|
| Task complete | Your prompt + Claude's response summary |
| Input needed | What Claude needs (with cooldown to prevent spam) |
| Permission needed | Tool name + command/file preview |

</details>

<details>
<summary>Self-teaching — how Claude gets smarter each session</summary>

Claude learns from your sessions and carries it forward:

| Signal | Example | Effect |
|---|---|---|
| Blocked commands | `rm -rf /` blocked by safety hook | "Don't attempt this again" |
| User corrections | "don't add comments to my code" | "Respect this preference" |
| Positive reinforcement | "perfect, keep doing that" | "Keep this approach" |
| Repeated failures | Same command fails 3x | Live nudge: "try a different approach" |

All four signals injected at session start.

</details>

<details>
<summary>4-layer defense — injection and secret protection</summary>

| Layer | When | What it catches |
|---|---|---|
| Config scan | Session start | Injection patterns planted in repo CLAUDE.md files |
| Code scan | Before Write/Edit | Insecure code patterns (eval, innerHTML, SQL injection, hardcoded secrets) |
| Runtime scan | MCP/web tool output | "Ignore previous instructions" and similar attacks |
| Secret scan | Bash/Read tool output | Leaked credentials — warns Claude not to repeat them |

### Why not just `/permissions`?

Claude's built-in permissions run **inside** the conversation — Claude sees the rules and can reason around them. Supercharger hooks run **outside** at the shell level. Claude never sees blocked commands.

| `/permissions` (inside) | Supercharger hooks (outside) |
|---|---|
| Claude sees the rules | Claude never sees them |
| Can reason and negotiate | Can't argue with exit code 2 |
| Advisory — Claude decides | Enforced — shell decides |

Use both. `/permissions` for convenience (wildcard approvals). Supercharger for safety (hard blocks).

</details>

<details>
<summary>Code security scanner — what it checks in Claude's output</summary>

Scans the code Claude **writes** (not just the commands it runs) for common vulnerabilities:

`eval()` · `.innerHTML` · `pickle.load()` · SQL injection via string concat · hardcoded secrets · `os.system()` · weak crypto (MD5) · GitHub Actions injection

Warns Claude to reconsider — doesn't block, since patterns like `eval()` are legitimate in test files.

</details>

<details>
<summary>Token optimization — loop and re-read detection</summary>

**Loop detector** catches repeated tool calls and breaks the cycle. Saves 10–50K tokens per loop.

**Re-read detector** warns when Claude re-reads unchanged files — nudges it to use cached knowledge instead.

Both are Full mode only.

</details>

<details>
<summary>Full mode features — complete list</summary>

**Context advisor** — warns at 50% context, suggests `/compact` at 70%, recommends `eco minimal` at 80%, critical warning at 90%. Reminds to verify work before compacting.

**Verify on stop** — checks the audit trail when Claude finishes. If files were modified but no test/build command ran, shows a warning.

**Scope alerts** — warns when Claude touches more than 5 files.

**Quality gate** — lint and format check after file edits. Developer role only.

**Traceback compressor** — 50KB Python stacktrace → 1-line summary. Same for Node.js.

**Token optimization** — loop detector + re-read detector (see section above).

**Audit trail** — every file write and command logged to JSONL. Credentials auto-redacted. 30-day rotation.

**Git safety** — blocks force-push to main/master, `reset --hard`, `checkout .`, `clean -f`.

**Failure tracking** — tracks repeated failures and nudges Claude to try a different approach after 3 attempts.

**MCP tracking** — active MCP server shown in the status bar.

</details>

<details>
<summary>Roles and slash commands</summary>

### Roles

Eight behavioral profiles, switchable mid-conversation:

`"as developer"` · `"as writer"` · `"as student"` · `"as data"` · `"as pm"` · `"as designer"` · `"as devops"` · `"as researcher"`

### Slash commands

| Command | Purpose |
|---|---|
| `/think [problem]` | Structured reasoning: clarify, inventory, hypotheses, stress-test |
| `/challenge [decision]` | Adversarial stress-test: assumptions, failure modes, alternatives |
| `/refactor [file]` | Code quality sweep: complexity, duplication, naming, coupling |
| `/audit [scope]` | Consistency sweep: naming, patterns, docs, interfaces |
| `/test [target]` | Generate unit tests for a file or function |
| `/doc [target]` | Generate documentation |

</details>

<details>
<summary>MCP servers — what gets auto-configured</summary>

Auto-configured based on roles. No API keys needed for the core set.

| Who | Servers |
|---|---|
| Everyone | Context7 (live docs), Sequential Thinking, Memory |
| Developer | + Playwright, Magic UI |
| Designer | + Magic UI |
| Other roles | + DuckDuckGo Search |

More servers: `bash tools/mcp-setup.sh`

</details>

<details>
<summary>Project config — per-repo settings</summary>

Drop `.supercharger.json` in your repo root:
```json
{"roles": ["developer", "designer"], "economy": "lean", "hints": "React + Tailwind, use pnpm"}
```
Commit it. Everyone on the team gets the same behavior.

</details>

<details>
<summary>Tools and tips</summary>

```bash
bash ~/.claude/supercharger/tools/update.sh          # self-update
bash ~/.claude/supercharger/tools/economy-switch.sh   # change tier permanently
bash ~/.claude/supercharger/tools/hook-toggle.sh      # enable/disable specific hooks
bash ~/.claude/supercharger/tools/config-health.sh    # installation health score
bash ~/.claude/supercharger/tools/mcp-setup.sh        # add MCP servers
bash ~/.claude/supercharger/tools/claude-check.sh     # full diagnostic
```

**Tips:**
- `/hooks` — inspect active hooks
- `/statusline` — customize your status bar
- `/permissions` — set wildcard rules: `Bash(npm run *)`, `Edit(/docs/**)`
- `/effort medium` — token savings alongside economy tiers
- `CLAUDE_CODE_SUBAGENT_MODEL=haiku` — cheaper sub-agents
- `MAX_THINKING_TOKENS=10000` — cap thinking token budget on Opus
- `/cost` — monitor token usage mid-session

</details>

<details>
<summary>FAQ</summary>

**Will this break my existing Claude setup?**
No. Backs up your config first. `./uninstall.sh` restores exactly what you had.

**A hook blocked something I need.**
`bash tools/hook-toggle.sh safety off` — or run the command in your terminal directly.

**How do I upgrade?**
`bash ~/.claude/supercharger/tools/update.sh`

**Does this touch my existing MCP servers?**
No. Supercharger tags its entries with `#supercharger`. Your servers stay untouched.

**Context overhead?**
~3,700 tokens per session (under 2% of any Claude model's context window). MCP tools load on first use, not at startup.

</details>

<details>
<summary>Requirements</summary>

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI
- Bash 3.2+ (macOS or Linux)
- Python 3 (ships with macOS)
- **Windows:** [WSL](https://learn.microsoft.com/en-us/windows/wsl/install) or Git Bash

</details>

<details>
<summary>Credits and license</summary>

Built on patterns from [SuperClaude](https://github.com/SuperClaude-Org/SuperClaude_Framework), [agent-guardrails-template](https://github.com/TheArchitectit/agent-guardrails-template), [Trail of Bits claude-code-config](https://github.com/trailofbits/claude-code-config), [claude-code-quality-hook](https://github.com/dhofheinz/claude-code-quality-hook), [prompt-master](https://github.com/nidhinjs/prompt-master), [oh-my-claudecode](https://github.com/Yeachan-Heo/oh-my-claudecode), [get-shit-done](https://github.com/gsd-build/get-shit-done), [claude-code-system-prompts](https://github.com/Piebald-AI/claude-code-system-prompts), [claude-code-tips](https://github.com/ykdojo/claude-code-tips), [claude-code-warp](https://github.com/warpdotdev/claude-code-warp) (notification patterns), [claude-guard](https://github.com/derek-larson14/claude-guard) (sensitive path blocking), [token-optimizer](https://github.com/alexgreensh/token-optimizer) (loop/reread detection patterns), and [CCNotify](https://github.com/dazuiba/CCNotify) (elapsed time in notifications).

MIT — see [LICENSE](LICENSE)

</details>
