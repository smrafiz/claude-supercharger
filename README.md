# Claude Supercharger

**Claude Code is capable of amazing things.**
It's also capable of deleting your files without asking, writing four paragraphs when you wanted one line, and treating a first-timer exactly like a senior engineer.

**One install fixes all three.**

Most AI behavior guides are suggestions. Claude can be talked out of them. Supercharger's guardrails run at the shell level — outside Claude's conversation context, before commands execute. Not a prompt it can be argued out of.

![Version](https://img.shields.io/badge/version-1.7.0-blue) ![License](https://img.shields.io/badge/license-MIT-green) ![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux-lightgrey) ![Tests](https://img.shields.io/badge/tests-227%20passing-brightgreen)

---

## Install

```bash
git clone https://github.com/smrafiz/claude-supercharger.git && cd claude-supercharger && ./install.sh
```

30 seconds. Four questions. Done.
Claude Code is now safer, smarter, and tailored to what you're actually working on.

<details>
<summary>Other install options</summary>

**One-liner** (temp clone, auto-clean):
```bash
bash -c 'TMP=$(mktemp -d) && git clone https://github.com/smrafiz/claude-supercharger.git "$TMP/cs" && "$TMP/cs/install.sh" && rm -rf "$TMP"'
```

**Non-interactive** (CI/scripts):
```bash
./install.sh --mode standard --roles developer --economy lean --config deploy --settings deploy
```

**Windows:** Use [WSL](https://learn.microsoft.com/en-us/windows/wsl/install) or Git Bash.
</details>

---

## Try these after installing

**Agents activate automatically — just talk naturally:**
```
"There's a null pointer at line 42"          → debugger agent
"Review this file for security issues"       → reviewer agent
"Add a login form to this page"              → code-helper agent
"Write a README for this project"            → writer agent
"Should I use REST or GraphQL here?"         → planner agent
"Compare Redis vs Memcached for our use case"→ researcher agent
```

**Commands — type them anywhere:**
```
/think Should we use a monorepo or separate repos?
/challenge We're going to rewrite the backend in Go
/refactor src/utils.ts
/audit src/
```

**Switch behavior mid-conversation:**
```
"as student"    → explains concepts, teaches step by step
"as pm"         → range estimates, decision logs, risk tracking
"eco minimal"   → telegraphic output, bare code only
"eco standard"  → back to full sentences
```

**MCP servers (auto-installed, no API keys):**
```
"Look up the React useEffect docs"        → live docs via Context7
"Test the login page in a real browser"   → Playwright automation
"Search for Tailwind grid examples"       → DuckDuckGo
"Remember that we use pnpm in this repo" → Memory across sessions
```

---

## What changes the moment you open Claude

No config. No prompts. No learning curve. Here's what happens automatically:

**First session — Claude introduces itself:**
> *"Claude Supercharger is active. Guardrails are on — I won't make destructive changes without asking. I verify before claiming done. Responses are lean by default."*

**Every session — Claude knows your project:**
Supercharger reads your project files and tells Claude what it's working with — React, Python, WordPress, Rust, Go, whatever. Claude adapts its behavior before you type a word.

**Every task — Claude uses the right agent:**
Writing something? The writer agent activates. Debugging? The debugger. Research? The researcher. You don't pick. Claude does.

**Four commands, always available:**
`/think` to reason through something hard. `/challenge` before committing to a decision. `/refactor` to analyze code quality. `/audit` to find inconsistencies. Type them in any project, any session.

---

## The three things Supercharger actually does

### 1. Guardrails that can't be argued with

Most Claude behavior guides are suggestions. Claude can be talked out of them.

Supercharger's guardrails are shell hooks — they run outside Claude, before the command executes. Claude cannot override them, no matter how you ask.

| What gets blocked | Why |
|---|---|
| `rm -rf /`, `DROP TABLE`, `chmod 777`, fork bombs | Irreversible destruction |
| `git push --force` to main/master | Overwrites shared history |
| `curl \| bash`, `eval`, credential patterns in commands | Security |
| `git reset --hard`, `git checkout .` | Loses uncommitted work |
| Wrong package manager (`npm` in a pnpm project) | Corrupts lockfile |
| Writing to `.bashrc`, `.zshrc`, SSH keys | Unauthorized persistence |

When something's blocked, you get a plain-English reason — not a shell error.

### 2. Eight agents. Zero selection required.

| Agent | Activates when you... |
|---|---|
| **code-helper** | Ask to build, fix, or implement anything |
| **debugger** | Share an error, stack trace, or "this isn't working" |
| **writer** | Ask to write, draft, or document something |
| **reviewer** | Ask to review or check something |
| **researcher** | Ask "what is", "compare", or "how does" |
| **planner** | Ask how to approach something or what steps to take |
| **data-analyst** | Share data, SQL, or ask "how many / show me" |
| **general** | Everything else — the default for non-technical users |

Each agent has focused instructions. Claude stops being a generalist and starts being exactly what the task needs.

### 3. Automatic project awareness

Supercharger detects your stack on every session start and tells Claude — no setup, no `.supercharger.json` required.

Detected automatically: TypeScript · React · Vue · Angular · Next.js · Python · Django · FastAPI · Flask · WordPress · Rust · Go · PHP

You see it in the status bar: `[sonnet] my-project | master | TypeScript, React`

---

## Before and after

<table>
<tr><th width="50%">Without Supercharger</th><th width="50%">With Supercharger</th></tr>
<tr><td>

**"Add a login form"**

"Here's the login form I've created for your authentication system. It includes email and password fields, client-side validation, and error handling. It *should* work correctly with your existing setup. Let me know if you need any changes!"

*No tests run. No build check. "Should work."*

</td><td>

**"Add a login form"**

`LoginForm.tsx` added. `npm test` — 3/3 pass. Build clean. Handles empty fields, invalid email, server errors.

*Verified. Specific. Done.*

</td></tr>
<tr><td>

**"Fix the typo in the header"**

"Fixed the typo. While I was at it, I also refactored the header component to use a more modern pattern, updated the styles to use Tailwind utility classes, and extracted the navigation into its own component for better reusability..."

*Nobody asked for that.*

</td><td>

**"Fix the typo in the header"**

Fixed `'Welcom'` → `'Welcome'` in `Header.tsx:12`. No other changes.

*Surgical. Stays in scope.*

</td></tr>
<tr><td>

**"Help me write a product description"**

"Certainly! Here is a comprehensive product description you can use. It covers the key features, benefits, target audience, and unique selling points. I've written it in a professional tone with multiple paragraphs..."

*Unprompted length, unknown audience, no iteration.*

</td><td>

**"Help me write a product description"**

Who's the audience and what's the tone? (casual / professional / technical)

*Asks first. Gets it right once.*

</td></tr>
</table>

---

## Works for everyone

You don't need to be a developer. Supercharger improves Claude for any kind of work.

| You do | What changes |
|---|---|
| **Write** (blogs, docs, emails) | Writer agent activates. Claude asks about your audience first. Short paragraphs, active voice, no filler. |
| **Research** (compare, summarize, explain) | Researcher agent activates. Claude leads with the answer, tables over prose, states what it doesn't know. |
| **Plan** (projects, decisions, approaches) | Planner agent activates. Numbered steps, flags the riskiest part, recommends the simplest path. |
| **Code** (build, debug, review) | Code agent + full guardrails. Stack auto-detected. Nothing deleted without asking. |
| **Anything else** | General agent. Plain language. No jargon. Asks one question if something's unclear. |

---

## Everything it installs

<details>
<summary>Hooks (shell-level enforcement)</summary>

| Hook | Event | What it does |
|---|---|---|
| **safety** | Before any command | Blocks dangerous patterns — rm -rf, credentials, fork bombs, self-modification |
| **git-safety** | Before any command | Blocks force-push to main, reset --hard, checkout ., clean -f |
| **enforce-pkg-manager** | Before any command | Blocks wrong package manager based on lockfile |
| **quality-gate** | After every file edit | Runs lint → auto-fix → re-check (ruff, eslint, clippy, rustfmt, gofmt) |
| **audit-trail** | After every mutation | Logs every file edit, commit, install to JSONL. 30-day rotation. |
| **prompt-validator** | Before every prompt | Scans for 20 anti-patterns — vague scope, missing context, multiple tasks |
| **project-config** | Session start | Detects stack, shows first-run welcome, loads .supercharger.json if present |
| **compaction-backup** | Before context compact | Saves session summary to `~/.claude/supercharger/summaries/` |
| **session-complete** | Session end | Saves metadata, fires webhook if configured |
| **notify** | Needs input | Desktop notification + optional Slack/Discord/Telegram |
| **statusline** | Always | 2-line status bar: model, project, branch, stack, context %, cost, cache rate |

Toggle any hook: `bash tools/hook-toggle.sh safety off`
</details>

<details>
<summary>8 Roles</summary>

| Role | Behavior |
|---|---|
| **Developer** | Code-only output, git best practices, stack detection, regression checks |
| **Writer** | Structured prose, asks about audience first, no jargon |
| **Student** | Explains before code, checks understanding, builds gradually |
| **Data** | Tables over prose, shows queries, cites assumptions |
| **PM** | Range estimates, decision logs, risk tracking |
| **Designer** | Component-first, accessibility, design tokens |
| **DevOps** | IaC, Docker, CI/CD, least privilege |
| **Researcher** | Citations, methodology, evidence-based claims |

Switch mid-conversation: `"as developer"` / `"as writer"` / etc.
Set at install. Change with `./install.sh`.
</details>

<details>
<summary>Token Economy</summary>

| Tier | What changes |
|---|---|
| **Standard** | Concise English. Complete sentences. Good for learning. |
| **Lean** *(default)* | Every word earns its place. Fragments OK. |
| **Minimal** | Telegraphic. Bare output only. |

Role constraints apply — Student can't go below Standard (explanations need space).

Switch anytime: `eco lean` / `eco standard` / `eco minimal`
Switch permanently: `bash tools/economy-switch.sh lean`
</details>

<details>
<summary>MCP Servers (auto-configured, no API keys)</summary>

| Who gets it | Servers |
|---|---|
| Everyone | Context7 (live docs), Sequential Thinking, Memory |
| Developer | + Playwright (browser automation), Magic UI (components) |
| Writer / Student / PM / Designer / Researcher | + DuckDuckGo Search |
| Advanced | Brave, Notion, Sentry, Figma, Slack — `bash tools/mcp-setup.sh` |

</details>

<details>
<summary>Profiles & Team Sharing</summary>

Bundle role + economy into one named profile:

```bash
bash tools/profile-switch.sh frontend-dev    # Developer+Designer, Lean
bash tools/profile-switch.sh --save my-setup # save current config as profile
```

Per-project config — drop `.supercharger.json` in your project root:
```json
{"roles": ["developer", "designer"], "economy": "lean", "hints": "React + Tailwind, use pnpm"}
```

Share with teammates:
```bash
bash tools/export-preset.sh team.supercharger
bash tools/import-preset.sh team.supercharger
```
</details>

<details>
<summary>Commands — /think, /refactor, /challenge, /audit</summary>

**Four reusable workflows**, installed automatically. Type them in any Claude Code session.

| Command | What it does |
|---|---|
| `/think [problem]` | Structured reasoning: clarify → hypotheses → stress-test → decide. For ambiguous problems. |
| `/refactor [file or dir]` | Code quality sweep across 7 dimensions. Prioritized findings, read-only. |
| `/challenge [decision]` | Adversarial stress-test. Assumptions, failure modes, strongest alternative, verdict. |
| `/audit [file or dir]` | Inconsistency sweep: naming, patterns, docs, interfaces, structure. Flags divergences. |

These live in `~/.claude/commands/` and work in every project without setup.

</details>

<details>
<summary>Project Agents — scaffold a specialist team for any repo</summary>

**One command gives your project a full agent team**, pre-wired with project name, stack, and file paths.

```bash
# Run from inside any project
bash /path/to/claude-supercharger/tools/init-agents.sh
```

Auto-detects your stack and scaffolds `.claude/agents/` with the right specialists:

| Stack | Agents scaffolded |
|-------|-------------------|
| Node / TypeScript / React | orchestrator, architect, frontend-engineer, backend-engineer, debugger, code-reviewer, qa-engineer |
| Python | orchestrator, architect, backend-engineer, debugger, code-reviewer, qa-engineer |
| Rust / Go | orchestrator, architect, systems-engineer, debugger, code-reviewer, qa-engineer |
| WordPress / PHP | orchestrator, architect, frontend-engineer, backend-engineer, debugger, code-reviewer |

Every agent has project-specific scope (no cross-contamination), numbered rules (Rule 0 = safety), escalation blocks, and done checklists. Drop `.claude/agents/` in your repo to share with your team.

```bash
# Options
bash tools/init-agents.sh --stack react   # override detection
bash tools/init-agents.sh --dir ~/myapp   # target directory
bash tools/init-agents.sh --force         # overwrite existing
```

</details>

<details>
<summary>Session Intelligence</summary>

**Context survives compaction and rate limits.** Say `"session summary"` or let it trigger automatically. Claude generates a structured handoff with decisions made, files changed, what failed, and a paste-ready resume prompt.

```bash
bash tools/resume.sh        # latest summary + copy resume prompt
bash tools/resume.sh --list # browse past summaries
```

**Verification gate.** Claude has to prove it's done:
1. File exists at expected path
2. Real code — not stubs or TODOs
3. Wired — imports resolve, route registered, component used
4. Tests pass, build succeeds

</details>

---

## Install modes

| Mode | What you get |
|---|---|
| **Safe** | Configs + safety hooks. Nothing that auto-runs. |
| **Standard** | + git-safety, quality gate, pkg enforcement, audit trail, notifications. *Recommended.* |
| **Full** | + prompt validation, compaction backup, session-complete. Everything. |

---

## The vision

What if AI coding assistants actually did what you asked? Not what they interpreted. Not what seemed impressive. What you actually requested.

- **Respects scope** — fixes the typo, not the entire component
- **Verifies before claiming done** — runs tests, confirms builds pass
- **Asks when uncertain** — doesn't guess at intent
- **Protects your work** — won't delete, reset, or force-push without asking
- **Adapts to you** — different behavior for beginners vs. experienced users

This isn't about limiting Claude. It's about making Claude reliable.

Supercharger is open source, MIT licensed, and zero-dependency — shell scripts and config files only. No npm packages, no pip installs.

---

## FAQ

<details>
<summary>Will this break my existing Claude setup?</summary>
No. Supercharger backs up everything before touching it. Run <code>./uninstall.sh</code> to restore exactly what you had.
</details>

<details>
<summary>I'm not a developer. Is this for me?</summary>
Yes. Install it, choose "general" as your role, and Claude will just behave better — clearer answers, stays focused, asks before doing something you didn't ask for. You don't need to know what hooks or MCP servers are.
</details>

<details>
<summary>What if a hook blocks something I actually need?</summary>
<code>bash tools/hook-toggle.sh safety off</code> — re-enable with <code>on</code>. Or just run the command in your terminal directly.
</details>

<details>
<summary>Does this work with my existing MCP servers?</summary>
Yes. Supercharger tags its own entries with <code>#supercharger</code>. Yours are never touched.
</details>

<details>
<summary>How do I upgrade?</summary>
<code>git pull && ./install.sh</code>
</details>

<details>
<summary>How do I switch roles or economy tier?</summary>
Mid-conversation: <code>"as developer"</code> / <code>eco lean</code>
Permanent: <code>./install.sh</code> or <code>bash tools/economy-switch.sh lean</code>
</details>

<details>
<summary>What about commit trailers? (Co-Authored-By)</summary>
Disabled automatically. Your commits, your name.
</details>

---

## Uninstall

```bash
./uninstall.sh
```

Removes everything. Offers to restore your backup. Your own config is untouched.

---

## Requirements

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI
- Bash 3.2+ (macOS or Linux)
- Python 3 (ships with macOS and Claude Code)
- **Windows:** Use [WSL](https://learn.microsoft.com/en-us/windows/wsl/install) or Git Bash. Install Python from [python.org](https://python.org) if needed.

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for hook authoring, testing conventions, and the Python-in-Bash guidelines.

---

## Credits

Built on patterns from:

- [SuperClaude Framework](https://github.com/SuperClaude-Org/SuperClaude_Framework) (MIT) — execution workflow
- [TheArchitectit/agent-guardrails-template](https://github.com/TheArchitectit/agent-guardrails-template) (BSD-3) — Four Laws, autonomy levels
- [Trail of Bits claude-code-config](https://github.com/trailofbits/claude-code-config) — statusline, pkg enforcement, audit trail
- [claude-code-quality-hook](https://github.com/dhofheinz/claude-code-quality-hook) — quality gate pipeline
- [prompt-master](https://github.com/nidhinjs/prompt-master) — deep interview, verification gate
- [oh-my-claudecode](https://github.com/Yeachan-Heo/oh-my-claudecode) — keyword switching
- [get-shit-done](https://github.com/gsd-build/get-shit-done) — verification gate patterns
- [claude-code-system-prompts](https://github.com/Piebald-AI/claude-code-system-prompts) — safety hook patterns
- [claude-code-tips](https://github.com/ykdojo/claude-code-tips) — statusline context bar

## License

MIT — see [LICENSE](LICENSE)
