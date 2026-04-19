# Claude Supercharger

Shell-level guardrails for Claude Code. Install once, forget forever.

Claude Code has root access to your filesystem and git history. One bad command and you're spending hours recovering. Supercharger puts a wall between Claude and the damage — shell hooks that block before execution, not prompts Claude can talk its way around.

![Version](https://img.shields.io/badge/version-3.6.6-blue) ![License](https://img.shields.io/badge/license-MIT-green) ![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux-lightgrey) ![Tests](https://img.shields.io/badge/tests-255%20passing-brightgreen)

```bash
git clone https://github.com/smrafiz/claude-supercharger.git && cd claude-supercharger && ./install.sh
```

Two modes. A few questions. Done. `./uninstall.sh` reverses everything.

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

---

## What you get

### Auto-approve safe operations
No more clicking "approve" 50 times per session. `Read`, `Glob`, `Grep`, `git status`, `ls`, `cat`, test runners, and `curl` GET requests are auto-approved with permanent session rules — approved once, never asked again.

### Block dangerous commands
Shell hooks run before commands execute. Claude can't argue with them, override them, or charm its way past them.

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

### Desktop notifications

| When | Shows |
|---|---|
| Task complete | Your prompt + Claude's response summary |
| Input needed | What Claude needs (with cooldown to prevent spam) |
| Permission needed | Tool name + command/file preview |

### Self-teaching

Claude learns from your sessions and carries it forward:

| Signal | Example | Effect |
|---|---|---|
| Blocked commands | `rm -rf /` blocked by safety hook | "Don't attempt this again" |
| User corrections | "don't add comments to my code" | "Respect this preference" |
| Positive reinforcement | "perfect, keep doing that" | "Keep this approach" |
| Repeated failures | Same command fails 3x | Live nudge: "try a different approach" |

All four get logged and injected at the start of every new session. The more you use it, the fewer mistakes Claude repeats.

### Why not just `/permissions`?

Claude's built-in permissions run **inside** the conversation — Claude sees the rules and can reason around them. Supercharger hooks run **outside** at the shell level. Claude never sees blocked commands.

| `/permissions` (inside) | Supercharger hooks (outside) |
|---|---|
| Claude sees the rules | Claude never sees them |
| Can reason and negotiate | Can't argue with exit code 2 |
| Advisory — Claude decides | Enforced — shell decides |

Use both. `/permissions` for convenience (wildcard approvals). Supercharger for safety (hard blocks).

### Code security scanner

Scans the code Claude **writes** (not just the commands it runs) for common vulnerabilities:

`eval()` · `.innerHTML` · `pickle.load()` · SQL injection via string concat · hardcoded secrets · `os.system()` · weak crypto (MD5) · GitHub Actions injection

Warns Claude to reconsider — doesn't block, since patterns like `eval()` are legitimate in test files.

### 4-layer defense

| Layer | When | What it catches |
|---|---|---|
| Config scan | Session start | Injection patterns planted in repo CLAUDE.md files |
| Code scan | Before Write/Edit | Insecure code patterns (eval, innerHTML, SQL injection, hardcoded secrets) |
| Runtime scan | MCP/web tool output | "Ignore previous instructions" and similar attacks |
| Secret scan | Bash/Read tool output | Leaked credentials — warns Claude not to repeat them |

### Status bar

```
[Opus 4.6 (1M context)] myproject | main | TypeScript | Agent: Tony Stark | MCP: context7 | +156/-23
Context: ████████████░░░░░░░░ 60% (120.5K/200K) | 115.2K in / 5.3K out | cache 92% (~103.7K saved)
Cost: $2.45 | Time: 8m 12s | Session: 24% (resets: 3h 42m) · Weekly: 15%
```

Everything you'd check manually — context pressure, burn rate, cache efficiency, how close you are to the rate limit — in three lines. Each Claude session gets its own state, so running five instances doesn't cross wires.

---

## Two install modes

| Mode | Hooks | What you get |
|---|---|---|
| **Safe** | 8 | Command blocking, code security scanner, auto-approve, audit trail, traceback compression, injection scanning, secret scanning, config scan |
| **Full** | 30 | Everything above + git safety, agent routing, context advisor, quality gate, notifications, scope alerts, self-teaching, verify-on-stop, failure tracking, loop/re-read detection, MCP tracking |

Most people should start with Safe. If you're in Claude Code all day and want the statusline, notifications, and token optimization — switch to Full.

---

## The instructional layer

Everything above runs at the shell level — Claude can't bypass it. What follows is the opposite: prompt-level instructions that shape how Claude behaves. They work well in practice, but Claude could ignore them if it decided to. Think of it as the difference between a locked door and a sign that says "please knock."

### Token economy

| Tier | Style |
|---|---|
| **Standard** | Complete sentences. Explanations included. |
| **Lean** *(default)* | Every word earns its place. Fragments OK. |
| **Minimal** | Telegraphic. Bare output only. |

Switch mid-conversation: `eco lean` / `eco standard` / `eco minimal`

### Agent routing

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

---

## Full mode features

**Context advisor** — warns at 50% context, suggests `/compact` at 70%, recommends `eco minimal` at 80%, critical warning at 90%. Reminds to verify work before compacting.

**Verify on stop** — checks the audit trail when Claude finishes. If files were modified but no test/build command ran, shows a warning.

**Scope alerts** — warns when Claude touches more than 5 files.

**Quality gate** — lint and format check after file edits. Developer role only.

**Traceback compressor** — 50KB Python stacktrace → 1-line summary. Same for Node.js.

**Token optimization** — loop detector catches repeated tool calls (saves 10-50K tokens per loop). Re-read detector warns when Claude re-reads unchanged files — nudges it to use cached knowledge instead.

**Audit trail** — every file write and command logged to JSONL. Credentials auto-redacted. 30-day rotation.

---

## MCP servers

Auto-configured based on roles. No API keys needed for core set.

**Default profile: `light`** — context7 only (~300 token overhead per session).

| Profile | Servers | Token cost |
|---|---|---|
| `light` (default) | Context7 | ~300 |
| `dev` | + Playwright, GitHub, Magic UI | ~1,200 |
| `research` | + Memory, Sequential Thinking | ~1,500 |
| `full` | Everything | ~3,500 |

Role-based additions always apply on top of the profile:
- Developer → Playwright, Magic UI
- Designer → Magic UI
- Writer / PM / DevOps / Researcher → DuckDuckGo

Switch profile at any time (no reinstall needed):
```bash
bash tools/mcp-profile.sh light     # minimal — context7 only
bash tools/mcp-profile.sh dev       # + browser + GitHub + UI components
bash tools/mcp-profile.sh research  # + memory + sequential thinking
bash tools/mcp-profile.sh full      # everything
```
Takes effect on next Claude Code session.

More servers: `bash tools/mcp-setup.sh`

---

## Project config

Drop `.supercharger.json` in your repo root:
```json
{"roles": ["developer", "designer"], "economy": "lean", "hints": "React + Tailwind, use pnpm"}
```
Commit it. Everyone on the team gets the same behavior.

---

## Tools

```bash
bash ~/.claude/supercharger/tools/update.sh          # self-update
bash ~/.claude/supercharger/tools/economy-switch.sh   # change tier permanently
bash ~/.claude/supercharger/tools/hook-toggle.sh      # enable/disable specific hooks
bash ~/.claude/supercharger/tools/config-health.sh    # installation health score
bash ~/.claude/supercharger/tools/mcp-setup.sh        # add MCP servers
bash ~/.claude/supercharger/tools/claude-check.sh     # full diagnostic
```

**Tips:** Use `/hooks` to inspect active hooks. Use `/statusline` to customize your status bar. Use `/permissions` for wildcard rules: `Bash(npm run *)`, `Edit(/docs/**)`. Use `/effort medium` for token savings alongside economy tiers. Set `CLAUDE_CODE_SUBAGENT_MODEL=haiku` for cheaper sub-agents. Set `MAX_THINKING_TOKENS=10000` to cap thinking token budget on Opus. Use `/cost` to monitor token usage mid-session.

---

## FAQ

<details>
<summary>Will this break my existing Claude setup?</summary>
No. Backs up your config first. <code>./uninstall.sh</code> restores exactly what you had.
</details>

<details>
<summary>A hook blocked something I need</summary>
<code>bash tools/hook-toggle.sh safety off</code> — or run the command in your terminal directly.
</details>

<details>
<summary>How do I upgrade?</summary>
<code>bash ~/.claude/supercharger/tools/update.sh</code>
</details>

<details>
<summary>Does this touch my existing MCP servers?</summary>
No. Supercharger tags its entries with <code>#supercharger</code>. Your servers stay untouched.
</details>

<details>
<summary>Context overhead?</summary>
~300–3,500 tokens per session depending on MCP profile (light to full). Switch profiles with `bash tools/mcp-profile.sh`.
</details>

---

## Requirements

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI
- Bash 3.2+ (macOS or Linux)
- Python 3 (ships with macOS)
- **Windows:** [WSL](https://learn.microsoft.com/en-us/windows/wsl/install) or Git Bash

---

## Credits

Built on patterns from [SuperClaude](https://github.com/SuperClaude-Org/SuperClaude_Framework), [agent-guardrails-template](https://github.com/TheArchitectit/agent-guardrails-template), [Trail of Bits claude-code-config](https://github.com/trailofbits/claude-code-config), [claude-code-quality-hook](https://github.com/dhofheinz/claude-code-quality-hook), [prompt-master](https://github.com/nidhinjs/prompt-master), [oh-my-claudecode](https://github.com/Yeachan-Heo/oh-my-claudecode), [get-shit-done](https://github.com/gsd-build/get-shit-done), [claude-code-system-prompts](https://github.com/Piebald-AI/claude-code-system-prompts), [claude-code-tips](https://github.com/ykdojo/claude-code-tips), [claude-code-warp](https://github.com/warpdotdev/claude-code-warp) (notification patterns), [claude-guard](https://github.com/derek-larson14/claude-guard) (sensitive path blocking), [token-optimizer](https://github.com/alexgreensh/token-optimizer) (loop/reread detection patterns), and [CCNotify](https://github.com/dazuiba/CCNotify) (elapsed time in notifications).

## License

MIT — see [LICENSE](LICENSE)
