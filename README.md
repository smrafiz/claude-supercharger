# Claude Supercharger

A role-aware, zero-dependency configuration kit for Claude Code. Drop it in, things get better.

![Version](https://img.shields.io/badge/version-1.1.0-blue) ![License](https://img.shields.io/badge/license-MIT-green) ![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux-lightgrey)

## The Problem

Claude Code claims tasks are "done" without verifying. It refactors code you didn't ask it to touch. It runs destructive commands without hesitation. And it gives the same response whether you're a senior developer or a student.

## Before and After

### Verification Gate

**Prompt:** "Add a login form to the app"

**Before:** "Here's the login form component I've created. It should work correctly with your authentication system."

**After:** "Login form added to `src/components/LoginForm.tsx`. Ran `npm test` — 3/3 tests pass. Ran `npm run build` — no errors. Form handles empty fields, invalid email format, and server errors. Try it: `npm run dev` and navigate to `/login`."

### Scope Discipline

**Prompt:** "Fix the typo in the header"

**Before:** "Fixed the typo. While I was there, I also refactored the header component to use a more modern pattern, updated the CSS to use Tailwind, and extracted the navigation into a separate component."

**After:** "Fixed 'Welcom' to 'Welcome' in `src/components/Header.tsx:12`. No other changes. (Also noticed the nav links could use `aria-label` attributes — want me to add those?)"

### Token Economy

**Prompt:** "Did the tests pass?"

**Before:** "I ran the test suite and I'm happy to report that all tests passed successfully. The test runner executed 57 test cases across 4 test files, and each one completed without any errors. This means our changes are working correctly and haven't introduced any regressions. Let me know if you'd like me to look at anything else!"

**After:** "Yes. 57 passed, 0 failed."

### Role: Student

**Prompt:** "How do I center a div?"

**Before:** `.container { display: grid; place-items: center; }`

**After:** "Great question! Centering is something every web developer needs. Let's build up to it. First, do you know what `display` does in CSS? ..." (explains concepts, checks understanding, suggests what to try next)

[More examples](docs/examples.md)

---

## Quick Install

```bash
curl -fsSL https://raw.githubusercontent.com/smrafiz/claude-supercharger/master/install.sh | bash
```

Or clone and review first:
```bash
git clone https://github.com/smrafiz/claude-supercharger.git
cd claude-supercharger && ./install.sh
```

Non-interactive:
```bash
./install.sh --mode standard --roles developer,pm --economy lean --config deploy --settings deploy
```

---

## What You Get

**For everyone:** Safety hooks (block `rm -rf`, `DROP TABLE`), verification gates, anti-pattern detection, **tiered token economy** (Standard/Lean/Minimal — 30-60% output reduction), **auto-configured MCP servers** (zero-setup), context management, quick mode switches, session handoff

**For developers:** Git safety, auto-format (Prettier/Black/rustfmt/gofmt), stack detection, regression prevention, scope discipline

**For writers:** Structured prose, draft versioning, source citation, no jargon

**For students:** Teach-first approach, guided learning, understanding checks

**For data analysts:** Analysis rigor, reproducibility, data validation

**For PMs:** Range estimates, decision logs, risk management

---

## Install Modes

| Mode | What it adds | What it skips |
|------|-------------|---------------|
| **Safe** | Configs + safety hooks | No notifications, no auto-format, no prompt checking |
| **Standard** | + notifications, git-safety, auto-format | No prompt checking, no compaction backup |
| **Full** | + prompt validation, compaction backup, diagnostics | Nothing — everything installed |

## Roles

| Role | Who it's for |
|------|-------------|
| **Developer** | Engineers — code-only output, git safety, auto-format |
| **Writer** | Content creators — structured prose, draft workflow |
| **Student** | Learners — explanations first, progressive complexity |
| **Data** | Analysts — reproducibility, data validation, tables |
| **PM** | Project managers — range estimates, decision logs, risk tracking |

Select one or more during installation. Switch mid-conversation by saying "as developer", "as student", etc. Claude honors these in most contexts — if it doesn't respond to a switch, repeat the keyword at the start of your next message.

## Token Economy

Three tiers of output compression, selectable at install and switchable mid-conversation:

| Tier | Reduction | Character |
|------|-----------|-----------|
| **Standard** | ~30% | Concise, natural English. Complete sentences. |
| **Lean** | ~45% | Every word load-bearing. Fragments OK. Default. |
| **Minimal** | ~60% | Telegraphic. Bare deliverables only. |

Each tier defines rules for 5 output types: **Code**, **Commands**, **Explanation**, **Diagnosis**, **Coordination**.

**Role-aware constraints** prevent bad combinations. Student floors at Standard (explanations need room). Writer floors at Standard (prose needs sentences). Developer/Data/PM are unrestricted.

Switch mid-conversation by saying `eco standard`, `eco lean`, or `eco minimal`.

Switch permanently: `bash tools/economy-switch.sh [standard|lean|minimal]`

## Hooks

| Hook | Modes | What it does |
|------|-------|-------------|
| **safety** | All | Blocks destructive commands (`rm -rf`, `DROP TABLE`, `chmod 777`, etc.) |
| **notify** | Standard+ | Desktop notification when Claude needs input |
| **git-safety** | Standard+ | Blocks force-push to main, `git reset --hard`, `git checkout .` |
| **auto-format** | Standard+ | Runs project formatter after edits (Developer role only) |
| **prompt-validator** | Full | Scans prompts for anti-patterns, suggests improvements |
| **compaction-backup** | Full | Saves transcript before context compaction |

## MCP Servers

Supercharger auto-configures MCP servers during install — zero API keys, zero JSON editing.

| Tier | Servers | Setup |
|------|---------|-------|
| **Core** (all roles) | Context7, Sequential Thinking, Memory | Automatic |
| **Developer** | + Playwright, Magic UI | Automatic |
| **Writer/Student/Data/PM** | + DuckDuckGo Search | Automatic |
| **Advanced** | GitHub, Brave Search, Slack, Notion, + more | `bash tools/mcp-setup.sh` |

Total: 3-5 servers per role (research shows 3 is the sweet spot, 5 is the max before token overhead).

---

## How It Works

Deploys to `~/.claude/` using Claude Code's native config system:

```
~/.claude/
  CLAUDE.md                  # Universal config (merged with yours if exists)
  rules/
    supercharger.md          # Execution workflow, anti-patterns
    guardrails.md            # Four Laws, autonomy levels, halt conditions
    economy.md               # Token economy (universal rules + active tier)
    developer.md             # Your selected role(s)
    anti-patterns.yml        # 35 prompt anti-pattern library
  supercharger/
    hooks/                   # Hook scripts referenced by settings.json
    roles/                   # All role files (for mode switching)
    economy/                 # Tier templates (for switching)
  settings.json              # Hooks registered here
```

Files in `~/.claude/rules/` are automatically loaded by Claude Code. Hooks execute deterministically on every tool use.

## Existing Config

| Scenario | What happens |
|----------|-------------|
| No existing config | Supercharger's deployed directly |
| Merge | Your content preserved, Supercharger appended below a marker |
| Replace | Your file backed up, Supercharger's deployed |
| Skip | Your file untouched, everything else installed |

A timestamped backup is always created first.

## Verify

```bash
bash tools/claude-check.sh
```

## Uninstall

```bash
./uninstall.sh
```

Removes all Supercharger content, preserves your configs, offers backup restore.

## Requirements

- Claude Code (Anthropic's CLI)
- Bash (macOS or Linux)
- Python 3 (for JSON operations — comes with Claude Code)

## FAQ

**Will this break my existing setup?** No. Everything is backed up first. Uninstall restores everything.

**How do I change roles?** Run `./install.sh` again — it's idempotent.

**How do I upgrade?** `git pull && ./install.sh`

**How do I change the token economy tier?** Say `eco lean` mid-conversation, or run `bash tools/economy-switch.sh lean` for a permanent change.

**What if a hook blocks something I need?** Run the command directly in your terminal (outside Claude Code), or remove the hook from `~/.claude/settings.json`.

---

## Credits

- [SuperClaude Framework](https://github.com/SuperClaude-Org/SuperClaude_Framework) (MIT) — execution workflow patterns, anti-patterns library
- [TheArchitectit/agent-guardrails-template](https://github.com/TheArchitectit/agent-guardrails-template) (BSD-3) — Four Laws, halt conditions, autonomy levels
- [oh-my-claudecode](https://github.com/Yeachan-Heo/oh-my-claudecode) (MIT) — magic keyword switching, clarification mode, session handoff patterns

## License

MIT — see [LICENSE](LICENSE)
