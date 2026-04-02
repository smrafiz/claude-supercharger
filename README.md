# Claude Supercharger

**Claude Code is powerful. It's also reckless, verbose, and treats everyone the same.**

Supercharger fixes that. It adds the guardrails, output discipline, and role awareness that Claude Code should have shipped with — through deterministic hooks that can't be talked past, not suggestions that get ignored.

Zero dependencies. 30-second install. Clean uninstall. Everything backed up.

![Version](https://img.shields.io/badge/version-1.5.0-blue) ![License](https://img.shields.io/badge/license-MIT-green) ![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux-lightgrey) ![Tests](https://img.shields.io/badge/tests-150%20passing-brightgreen)

---

## The Problem

I got tired of Claude Code:

- Saying **"should work"** without running a single test
- **Refactoring code I didn't ask it to touch** — the classic "while I was here..." move
- Running `rm -rf` and `git push --force` **without blinking**
- Writing **four paragraphs** when one line would do
- Giving a **senior engineer and a student** the exact same response
- **Losing everything** when the session ends or hits a rate limit

So I built this.

---

## Before / After

<table>
<tr><td width="50%">

**You:** "Add a login form"

**Claude:** "Here's the login form I've created. It should work correctly with your authentication system."

*No tests. No verification. "Should work."*

</td><td width="50%">

**You:** "Add a login form"

**Claude:** "Login form added to `LoginForm.tsx`. `npm test` — 3/3 pass. Build clean. Handles empty fields, invalid email, server errors."

*Verified. Specific. Done.*

</td></tr>
<tr><td>

**You:** "Did the tests pass?"

**Claude:** "I ran the test suite and I'm happy to report that all tests passed successfully. The test runner executed 57 test cases across 4 test files, and each one completed without any errors. This means our changes are working correctly..."

*73 words for a yes/no question.*

</td><td>

**You:** "Did the tests pass?"

**Claude:** "Yes. 57 passed, 0 failed."

*Done.*

</td></tr>
<tr><td>

**You:** "Fix the typo in the header"

**Claude:** "Fixed the typo. While I was there, I also refactored the header to use a modern pattern, updated the CSS to Tailwind, and extracted the nav..."

*Nobody asked for that.*

</td><td>

**You:** "Fix the typo in the header"

**Claude:** "Fixed 'Welcom' → 'Welcome' in `Header.tsx:12`. No other changes."

*Surgical. Stays in scope.*

</td></tr>
</table>

[More examples →](docs/examples.md)

---

## Install

```bash
git clone https://github.com/smrafiz/claude-supercharger.git && cd claude-supercharger && ./install.sh
```

The installer walks you through 4 choices: install mode → roles → economy tier → config handling. About 30 seconds.

<details>
<summary>Other install options</summary>

**One-liner** (temp clone, install, clean up):
```bash
bash -c 'TMP=$(mktemp -d) && git clone https://github.com/smrafiz/claude-supercharger.git "$TMP/cs" && "$TMP/cs/install.sh" && rm -rf "$TMP"'
```

**Non-interactive** (CI/scripted):
```bash
./install.sh --mode standard --roles developer,pm --economy lean --config deploy --settings deploy
```

**Windows:** Use [WSL](https://learn.microsoft.com/en-us/windows/wsl/install) or Git Bash.
</details>

---

## What You Actually Get

### Hooks That Actually Block Things

These aren't suggestions. They run on every command, every time. Claude can't override them.

| Hook | What it stops |
|------|--------------|
| **safety** | `rm -rf /`, `DROP TABLE`, `chmod 777`, fork bombs, `curl \| bash`, credential leaks, SSH key ops, self-modification — and handles bypass attempts (`sudo`, `command`, `env` prefixes) |
| **git-safety** | Force-push to main/master, `git reset --hard`, `git checkout .`, `git clean -f` |
| **enforce-pkg-manager** | `npm install` in a pnpm project, `pip install` in a uv project — detects from lockfiles |
| **quality-gate** | Doesn't block — runs lint→auto-fix→re-check after every edit (ruff, eslint, clippy, rustfmt, gofmt) |
| **audit-trail** | Doesn't block — logs every mutation as JSONL with 30-day rotation |
| **prompt-validator** | Scans your prompts for 20 anti-patterns before Claude sees them |
| **session-complete** | Doesn't block — saves session metadata and sends webhook on exit |
| **notify** | Desktop notification + optional webhook (Slack/Discord/Telegram) when Claude needs input |

Toggle any hook: `bash tools/hook-toggle.sh safety off`

### 8 Roles — Because Not Everyone Writes Code

| Role | What changes |
|------|-------------|
| **Developer** | Code-only output, git best practices, stack detection, regression checks |
| **Writer** | Structured prose, asks about audience first, draft versioning, no jargon |
| **Student** | Explains concepts before code, checks understanding, builds complexity gradually |
| **Data** | Tables over prose, shows queries, cites assumptions, statistical rigor |
| **PM** | Range estimates, decision logs, risk tracking, bullet-only output |
| **Designer** | Component-first, accessibility, design tokens, visual hierarchy |
| **DevOps** | IaC, Docker best practices, CI/CD, security scanning, least privilege |
| **Researcher** | Citations, methodology, evidence-based claims, reproducibility |

Pick during install. Switch mid-conversation: `"as developer"`, `"as designer"`, etc.

### Token Economy — Claude Talks Less, Says More

| Tier | What it does |
|------|-------------|
| **Standard** (~30% reduction) | Concise English. Complete sentences. Good for learning. |
| **Lean** (~45% reduction) | Every word earns its place. Fragments OK. *Default.* |
| **Minimal** (~60% reduction) | Telegraphic. Bare output only. |

Rules are per output type — Code, Commands, Explanation, Diagnosis, Coordination each have their own targets. Role constraints prevent bad combos (Student can't go below Standard — explanations need room).

Switch anytime: `eco lean` / `eco standard` / `eco minimal`

### Session Intelligence

**Your context survives.** When a session compacts, hits a rate limit, or you say `"session summary"`, Claude generates a structured handoff with decisions, files changed, what failed, and a paste-ready resume prompt.

```bash
bash tools/resume.sh        # show latest summary, copy resume prompt to clipboard
bash tools/resume.sh --list  # see all saved summaries
```

**Vague prompts get caught.** Every prompt is scanned for missing scope, unclear success criteria, and multiple tasks crammed together. For complex work, say `"deep interview"` — Claude scores your prompt across 9 dimensions and asks targeted questions before writing a line of code.

### Verification Gate

Claude has to prove it's done, not just claim it. Four levels:

1. **Exists** — file is at the expected path
2. **Substantive** — real code, not stubs or TODOs
3. **Wired** — imports resolve, component is used, route is registered
4. **Functional** — tests pass, build succeeds, endpoint responds

### Webhook Notifications

Get notified on Slack, Discord, Telegram, or any webhook URL when Claude needs input or finishes a session.

```bash
bash tools/webhook-setup.sh          # interactive setup
bash tools/webhook-setup.sh test     # send a test message
bash tools/webhook-setup.sh disable  # turn off temporarily
```

### Clean Git History

Supercharger disables Claude's Co-Authored-By commit trailers automatically. Your commits, your name.

### Profiles & Teams

Bundle role + economy into named profiles. Switch everything with one command:

```bash
bash tools/profile-switch.sh frontend-dev   # Developer+Designer, Lean
bash tools/profile-switch.sh --save my-setup # save current config
```

Drop `.supercharger.json` in a project root — Claude picks it up on session start:

```json
{"roles": ["developer", "designer"], "economy": "lean", "hints": "React + Tailwind, use pnpm"}
```

Share configs with teammates:

```bash
bash tools/export-preset.sh team.supercharger   # export
bash tools/import-preset.sh team.supercharger   # import
```

### MCP Servers (Auto-Configured)

3-5 servers added during install. No API keys, no JSON editing.

| Who | Servers |
|-----|---------|
| Everyone | Context7, Sequential Thinking, Memory |
| Developer | + Playwright, Magic UI |
| Non-dev roles | + DuckDuckGo Search |
| Advanced | Brave Search, Notion, Sentry, Figma, Slack — `bash tools/mcp-setup.sh` |

### 30+ Anti-Patterns

A YAML library of prompt anti-patterns that Claude reads as context. It learns *why* patterns like "fix it" or "build the whole thing" are bad, and what to ask instead. Separate from the prompt-validator hook — soft guidance vs. hard enforcement.

---

## All the Tools

| Tool | What it does |
|------|-------------|
| `bash tools/supercharger.sh` | One-screen overview of everything you can do |
| `bash tools/claude-check.sh` | Health check + "features you're not using" |
| `bash tools/economy-switch.sh lean` | Change economy tier permanently |
| `bash tools/resume.sh` | Retrieve session summaries |
| `bash tools/hook-toggle.sh safety off` | Enable/disable any hook |
| `bash tools/profile-switch.sh frontend-dev` | Switch role+economy in one command |
| `bash tools/webhook-setup.sh` | Set up Slack/Discord/Telegram notifications |
| `bash tools/export-preset.sh team.supercharger` | Export config for sharing |
| `bash tools/import-preset.sh team.supercharger` | Import a teammate's config |
| `bash tools/mcp-setup.sh` | Add advanced MCP servers (API keys needed) |

---

## Install Modes

| Mode | What you get |
|------|-------------|
| **Safe** | Configs + safety hooks. Nothing that auto-runs or notifies. |
| **Standard** | + notifications, git-safety, quality gate, pkg-manager enforcement, audit trail. *Recommended.* |
| **Full** | + prompt validation, compaction backup, session-complete hook. Everything. |

---

## How It Works

Everything deploys to `~/.claude/` — Claude Code's native config directory:

```
~/.claude/
  CLAUDE.md                  # Universal config (merged if yours exists)
  rules/
    supercharger.md          # Execution workflow, clarification, session summary
    guardrails.md            # Four Laws, stop conditions, autonomy levels
    economy.md               # Token economy rules + active tier
    [role].md                # Your selected roles
    anti-patterns.yml        # 30+ prompt anti-patterns
  supercharger/
    hooks/                   # Hook scripts (referenced by settings.json)
    roles/                   # All 8 roles (for mid-conversation switching)
    economy/                 # Tier templates (for economy switching)
    summaries/               # Session summaries
    audit/                   # Mutation log (JSONL, 30-day rotation)
    profiles/                # Named profiles
  settings.json              # Hooks, MCP servers, statusline, attribution
```

Files in `rules/` are auto-loaded by Claude Code. Hooks run deterministically. MCP servers are tagged with `#supercharger` for clean add/remove. Everything is idempotent.

---

## Your Existing Config

| Choice | What happens |
|--------|-------------|
| **Merge** | Your config preserved. Supercharger appended below a marker. |
| **Replace** | Your file backed up first. Supercharger's deployed. |
| **Skip** | Your file untouched. Everything else still installs. |

Backup is always created first. Always.

---

## FAQ

<details>
<summary><strong>Will this break my setup?</strong></summary>
No. Backup before any changes. Uninstall restores everything. Supercharger content is tagged so it never touches your own config.
</details>

<details>
<summary><strong>How do I change roles?</strong></summary>
Mid-conversation: say "as developer", "as student", etc. Permanent: re-run <code>./install.sh</code>.
</details>

<details>
<summary><strong>How do I upgrade?</strong></summary>
<code>git pull && ./install.sh</code>
</details>

<details>
<summary><strong>How do I change the economy tier?</strong></summary>
Mid-conversation: <code>eco lean</code>. Permanent: <code>bash tools/economy-switch.sh lean</code>.
</details>

<details>
<summary><strong>What if a hook blocks something I need?</strong></summary>
<code>bash tools/hook-toggle.sh safety off</code> — re-enable with <code>on</code>. Or run the command in your terminal directly.
</details>

<details>
<summary><strong>Does this work with my existing MCP servers?</strong></summary>
Yes. Supercharger entries are tagged. Your servers are never touched.
</details>

<details>
<summary><strong>How do I resume after a rate limit?</strong></summary>
Claude generates a session summary automatically. Run <code>bash tools/resume.sh</code> to get it and copy the resume prompt to your clipboard.
</details>

<details>
<summary><strong>Can I disable the Co-Authored-By commit trailers?</strong></summary>
Already done. Supercharger sets <code>attribution.commit</code> and <code>attribution.pr</code> to empty strings in settings.json.
</details>

---

## Uninstall

```bash
./uninstall.sh
```

Removes everything. Offers backup restore. Your own config stays untouched.

---

## Requirements

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) (Anthropic's CLI)
- Bash 3.2+ (macOS or Linux)
- Python 3 (ships with Claude Code)
- **Windows (Git Bash):** Python must be installed and on PATH as `python` — the installer auto-creates a `python3` shim. If you see *"Python was not found"*, install Python from [python.org](https://python.org) and ensure it's on PATH.

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for hook authoring, testing conventions, and the Python-in-Bash rules.

---

## Credits

Built on patterns from:

- [SuperClaude Framework](https://github.com/SuperClaude-Org/SuperClaude_Framework) (MIT) — execution workflow, anti-patterns
- [TheArchitectit/agent-guardrails-template](https://github.com/TheArchitectit/agent-guardrails-template) (BSD-3) — Four Laws, autonomy levels
- [oh-my-claudecode](https://github.com/Yeachan-Heo/oh-my-claudecode) (MIT) — keyword switching, clarification mode
- [prompt-master](https://github.com/nidhinjs/prompt-master) — deep interview dimensions, verification gate
- [Trail of Bits claude-code-config](https://github.com/trailofbits/claude-code-config) — statusline, pkg-manager enforcement, audit trail
- [claude-code-quality-hook](https://github.com/dhofheinz/claude-code-quality-hook) — three-stage quality gate pipeline
- [get-shit-done](https://github.com/gsd-build/get-shit-done) — verification gate patterns
- [claude-code-system-prompts](https://github.com/Piebald-AI/claude-code-system-prompts) — safety hook patterns
- [claude-code-tips](https://github.com/ykdojo/claude-code-tips) — statusline context bar
- [agnix](https://github.com/agent-sh/agnix) — config validation concept
- ClaudeCTX (foxj77) — profile switching concept

## License

MIT — see [LICENSE](LICENSE)
