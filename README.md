# Claude Supercharger

Claude Code has root access to your filesystem and git history. One hallucinated `rm -rf ~`, one `git push --force main`, one committed API key — and you're spending hours recovering.

Supercharger stops that at the shell level. Hooks run before commands execute, outside Claude's conversation. Claude can't argue with them, override them, or charm its way past them. Exit code 2. Command blocked. Done.

![Version](https://img.shields.io/badge/version-3.3.1-blue) ![License](https://img.shields.io/badge/license-MIT-green) ![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux-lightgrey) ![Tests](https://img.shields.io/badge/tests-255%20passing-brightgreen)

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

## Two layers

**Layer 1 — Enforced.** Shell hooks that block dangerous commands. Claude doesn't see them, can't disable them, gets a plain-English reason when blocked.

**Layer 2 — Instructional.** Prompt configurations that shape Claude's behavior. Effective in practice, not physically enforced.

---

## What gets blocked

| Blocked | Why |
|---|---|
| `rm -rf /`, `rm -rf ~`, `DROP TABLE`, `chmod 777`, fork bombs | Irreversible destruction |
| `git push --force` to main/master | Overwrites shared history |
| `git reset --hard`, `git checkout .`, `git clean -f` | Loses uncommitted work |
| `curl \| bash`, `eval`, credential patterns (AWS keys, GitHub tokens, Stripe, JWTs) | Remote code execution, secret exposure |
| Wrong package manager (`npm` in a pnpm project) | Corrupts lockfile |
| Writing to `.bashrc`, `.zshrc`, SSH key operations | Unauthorized persistence |

All blocking happens at the shell level. Not a prompt Claude can reconsider — a wall it can't pass through.

---

## What gets auto-approved

Nobody wants to click "approve" 50 times for `git status` and `ls`.

Safe mode auto-approves: `Read`, `Glob`, `Grep`, read-only git commands (`status`, `log`, `diff`, `branch`), `ls`, `cat`, `head`, `tail`, test runners (`npm test`, `pytest`, `cargo test`), and `curl` GET requests.

Writes, installs, and destructive operations still require approval.

**Power users:** Complement smart-approve with Claude Code's built-in `/permissions` for wildcard patterns: `Bash(npm run *)`, `Bash(cargo test *)`, `Edit(/docs/**)`.

---

## Two install modes

| Mode | Hooks | What you get |
|---|---|---|
| **Safe** | 5 | Command blocking, auto-approve reads, audit trail, traceback compression, injection scanning |
| **Full** | 17 | Everything above + git safety, agent routing, context advisor, quality gate, notifications, scope alerts |

Safe mode is enough for most people. Full mode adds workflow features for daily Claude Code users.

---

## The instructional layer

### Token economy

Three tiers that control output verbosity:

| Tier | Style |
|---|---|
| **Standard** | Complete sentences. Explanations included. |
| **Lean** *(default)* | Every word earns its place. Fragments OK. |
| **Minimal** | Telegraphic. Bare output only. |

Switch mid-conversation: `eco lean` / `eco standard` / `eco minimal`

Permanent: `bash ~/.claude/supercharger/tools/economy-switch.sh minimal`

### Agent routing

Each prompt is classified by task type. Claude gets a hint — not a forced dispatch:

```
"null pointer at line 42"           → debugging task      (Sherlock Holmes)
"review this for security issues"   → review task         (Gordon Ramsay)
"add a login form"                  → engineering task    (Tony Stark)
"write a README"                    → writing task        (Ernest Hemingway)
"compare Redis vs Memcached"        → research task       (Marie Curie)
"design the auth system"            → architecture task   (Leonardo da Vinci)
"plan the rollout"                  → planning task       (Sun Tzu)
"analyze this CSV"                  → data analysis task  (Albert Einstein)
```

Nine agent files with scoped rules and verification checklists. Claude decides when a sub-agent is worth spawning — not every prompt needs one.

**Project agents take priority.** Drop `.claude/agents/my-agent.md` in your repo. Supercharger detects it and tells Claude to prefer project-specific agents over global ones.

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

**Context advisor** — warns when context window fills up. Suggests `/compact` at 50%, recommends economy tier change at 80%, critical warning at 90%.

**Scope alerts** — warns when Claude touches more than 5 files. Catches scope creep before it snowballs.

**Injection scanner** — scans MCP and web tool output for prompt injection patterns ("ignore previous instructions", token injection, etc.). Warns Claude to treat suspicious content as data, not instructions.

**Traceback compressor** — 50KB Python stacktrace becomes a 1-line summary. Same for Node.js error stacks. Saves context tokens on error-heavy sessions.

**Audit trail** — every file write and command logged to JSONL. Credentials auto-redacted. 30-day rotation.

**Quality gate** — lint and format check after file edits. Developer role only.

**Status bar** — model, project, branch, stack, agent, active MCP, context % with used/max tokens (color-coded), in/out token breakdown, cost, cache hit rate with savings estimate.

**Desktop notifications** — three types, no terminal-specific dependencies:

| Notification | When | Shows |
|---|---|---|
| Task complete | Claude finishes responding | Your prompt + Claude's response summary |
| Input needed | Claude is idle, waiting for you | What Claude needs (30s cooldown) |
| Permission needed | Claude wants to run a tool | Tool name + command/file preview |

Disable: `bash tools/notify-toggle.sh off`. Sound only: `bash tools/notify-toggle.sh sound`.

**Self-teaching** — Claude learns from 4 signals across sessions: blocked commands, user corrections ("don't do X"), positive reinforcement ("perfect, keep doing that"), and repeated command failures. All injected at session start.

---

## MCP servers

Auto-configured based on roles. No API keys needed for core set.

| Who | Servers |
|---|---|
| Everyone | Context7 (live docs), Sequential Thinking, Memory |
| Developer | + Playwright, Magic UI |
| Designer | + Magic UI |
| Other roles | + DuckDuckGo Search |

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

**Tips:** Use `/hooks` to inspect active hooks. Use `/statusline` to customize your status bar with natural language. Use `/permissions` to add wildcard rules beyond what smart-approve covers. Use `/effort medium` for additional token savings alongside economy tiers. Set `CLAUDE_CODE_SUBAGENT_MODEL=haiku` to run sub-agents on cheaper models.

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
~3,700 tokens per session (under 2% of any Claude model's context window). MCP tools load on first use, not at startup.
</details>

---

## Requirements

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI
- Bash 3.2+ (macOS or Linux)
- Python 3 (ships with macOS)
- **Windows:** [WSL](https://learn.microsoft.com/en-us/windows/wsl/install) or Git Bash

---

## Credits

Built on patterns from [SuperClaude](https://github.com/SuperClaude-Org/SuperClaude_Framework), [agent-guardrails-template](https://github.com/TheArchitectit/agent-guardrails-template), [Trail of Bits claude-code-config](https://github.com/trailofbits/claude-code-config), [claude-code-quality-hook](https://github.com/dhofheinz/claude-code-quality-hook), [prompt-master](https://github.com/nidhinjs/prompt-master), [oh-my-claudecode](https://github.com/Yeachan-Heo/oh-my-claudecode), [get-shit-done](https://github.com/gsd-build/get-shit-done), [claude-code-system-prompts](https://github.com/Piebald-AI/claude-code-system-prompts), [claude-code-tips](https://github.com/ykdojo/claude-code-tips), and [claude-code-warp](https://github.com/warpdotdev/claude-code-warp) (notification patterns).

## License

MIT — see [LICENSE](LICENSE)
