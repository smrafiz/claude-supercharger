# Claude Supercharger v1.0.0

**Transform Claude Code into a hyper-efficient AI coding assistant with advanced prompting patterns, anti-pattern detection, and intelligent automation.**

[![Version](https://img.shields.io/badge/version-1.0.0-blue.svg)](https://github.com/smrafiz/claude-supercharger)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

---

## What is Claude Supercharger?

Claude Supercharger is a comprehensive configuration system for Claude Code that provides:

- **35 Anti-Pattern Detection** → Automatically fixes vague requests, missing scope, and common errors
- **9-Dimensional Intent Extraction** → Structured requirement gathering (max 3 questions)
- **Tool-Specific Optimization** → Per-model constraints (Claude Opus 4.x, o3/o4-mini, GPT-5.x, Gemini, DeepSeek, Qwen, Ollama)
- **8-Step Execution Priority** → Systematic workflow from detection to delivery
- **10-Point Verification Gate** → Quality assurance before claiming "done"
- **Memory Block System** → Explicit context carry-forward for multi-turn sessions
- **9 Cognitive Personas** → Specialized behavioral profiles (architect, frontend, backend, analyzer, security, mentor, refactorer, performance, qa)
- **MCP Orchestration** → Intelligent routing for Context7, Sequential Thinking, Magic UI, Puppeteer (optional, requires MCP setup)
- **Output Lock Discipline** → Eliminates ceremonial text and unprompted explanations
- **Forbidden Techniques Enforcement** → Prevents fabrication-prone methods (Mixture of Experts, Tree of Thought, etc.)

---

## Features

### Core Systems

**Anti-Pattern Detection [H:8]**
- Scans requests for 35 credit-killing patterns across 6 categories
- Task: vague verbs, two tasks in one, no success criteria
- Context: assumed knowledge, hallucination invites, undefined audience
- Format: missing output format, implicit length, vague aesthetics
- Scope: no boundaries, no stop conditions, unlocked filesystem
- Reasoning: missing CoT for logic, CoT on reasoning models
- Agentic: no start/target state, silent agents, no review triggers

**Intent Extraction [H:7]**
- 9-dimension analysis: Task, Target tool, Output format, Constraints, Input, Context, Audience, Success criteria, Examples
- Max 3 clarifying questions before execution
- Risk-based response (HIGH→more questions, LOW→safe defaults)

**Verification Gate [H:8]**
- Technical: TypeScript compilation, tests, imports, git diff, no debug code
- Quality: Correct tool ID, constraints preserved, strong signal words, no fabrication, token efficiency, binary success

**Tool-Specific Optimization [M:6]**
- Claude Opus 4.x: Prevent over-engineering
- o3/o4-mini: SHORT instructions, no CoT (degrades output)
- GPT-5.x: Compact structured outputs, verbosity constraints
- Gemini 2.x/3 Pro: Grounding for hallucinated citations
- DeepSeek-R1, Qwen variants, Ollama: Model-specific guidance

### Personas (9 Archetypes)

1. **architect** → Systems design, long-term maintainability, proven patterns
2. **frontend** → UX-first, mobile-responsive, user satisfaction
3. **backend** → Reliability, performance, 10x scale planning
4. **analyzer** → Root cause identification, evidence-based debugging
5. **security** → Threat modeling, defense-in-depth, zero trust
6. **mentor** → Guided discovery, student context, adaptive teaching
7. **refactorer** → Code health, complexity reduction, maintainability
8. **performance** → Bottleneck identification, speed optimization, profiling
9. **qa** → Edge cases, quality gates, defect escape prevention

---

## Installation

### One-Command Install

```bash
curl -fsSL https://raw.githubusercontent.com/smrafiz/claude-supercharger/main/install.sh | bash
```

### Manual Install

```bash
# Clone repository
git clone https://github.com/smrafiz/claude-supercharger.git
cd claude-supercharger

# Backup existing config (optional but recommended)
mkdir -p ~/.claude/backups/$(date +%Y%m%d)
cp ~/.claude/*.md ~/.claude/backups/$(date +%Y%m%d)/ 2>/dev/null || true

# Install core files
cp core/CLAUDE.md ~/.claude/
cp core/RULES.md ~/.claude/
cp core/MCP.md ~/.claude/
cp core/PERSONAS.md ~/.claude/

# Install shared resources
mkdir -p ~/.claude/shared
cp shared/anti-patterns.yml ~/.claude/shared/

# Verify installation
grep "Claude Supercharger v1.0.0" ~/.claude/RULES.md
echo "✅ Claude Supercharger v1.0.0 (Claude Supercharger v1.0.0) installed successfully"
```

---

### Existing Configuration? Use Merge Mode

**If you already have custom CLAUDE.md, RULES.md, PERSONAS.md, or MCP configurations:**

```bash
# Clone repository
git clone https://github.com/smrafiz/claude-supercharger.git
cd claude-supercharger

# Smart merge (preserves your config + adds Supercharger enhancements)
bash merge.sh
```

**Or run install.sh** — it will detect existing files and offer merge option.

**Manual cherry-picking:** See [docs/MIGRATION.md](docs/MIGRATION.md) for full control over which features to integrate.

---

### Optional: MCP Server Setup

**Core features work immediately** (anti-pattern detection, verification gates, personas, etc.).

**Advanced MCP servers** add powerful capabilities:

```bash
# Interactive MCP server installation
cd claude-supercharger
bash mcp-setup.sh
```

**Recommended Stack (2026):**

**Tier 1 (Must-Have):**
- Context7 - Latest version-specific docs (React, Next.js, Prisma, etc.)
- Sequential Thinking - Multi-step reasoning framework
- Memory - Persistent knowledge graphs

**Tier 2 (Highly Useful):**
- GitHub - Repository operations, PRs, issues
- Brave Search - Current information beyond training cutoff
- Filesystem - Secure file operations

**Tier 3 (Specialized):**
- Playwright/Puppeteer - Browser automation
- Prisma/Neon - Database operations
- Magic UI - React component library
- Slack - Team communication context

**API Keys Required:** Context7, GitHub, Brave Search, Neon, Slack (all have free tiers)

See [docs/MCP_SETUP.md](docs/MCP_SETUP.md) for complete guide with API key setup, manual configuration, and troubleshooting.


## Quick Start

**Claude Supercharger activates automatically.** No configuration needed.

### Example 1: Automatic Anti-Pattern Correction

**You:** "fix the login bug"

**Before:** Random search, unclear scope

**After Claude Supercharger:** Detects "vague scope" anti-pattern → asks "Which file contains the login bug, and what's the symptom?" (max 3 questions)

### Example 2: Multi-Turn Context

**You:** "now add logout using the same pattern"

**Claude Supercharger prepends Memory Block:**
```
## Context (carry forward)
- Stack: React 18, TypeScript, Tailwind
- Auth pattern: JWT in httpOnly cookie
- Component location: src/components/auth/
- Already tried: localStorage (rejected for security)
```

### Example 3: Verification Before "Done"

**Claude Supercharger checks 10 items before claiming done:**
- ✓ tsc --noEmit passes
- ✓ Tests pass
- ✓ No debug code left
- ✓ Constraints preserved
- ✓ Token efficiency maintained
- ✓ Binary success criteria met

---

## Usage

### Activating Personas

Personas are activated through natural language:

```
You: "load the frontend persona"
→ Frontend persona active (UX-first, mobile-first, user needs > technical elegance)

You: "load the security persona"
→ Security persona active (threat modeling, defense-in-depth, assume breach)

You: "switch to architect persona"
You: "As performance mindset: optimize this query"
You: "With analyzer approach, debug this crash"
```

**Available personas:** architect, frontend, backend, analyzer, security, mentor, refactorer, performance, qa

**Auto-activation:** Claude Supercharger automatically adopts appropriate personas based on context (file types, keywords, task nature).

### Thinking Modes

Request deeper analysis naturally:

```
You: "Think deeply about this architecture decision"
You: "Analyze this thoroughly before implementing"
You: "Consider all implications of this refactor"
```

**Automatic activation:** Complex tasks trigger appropriate thinking depth automatically.

### MCP Servers (Optional)

If you've run `mcp-setup.sh`, MCP servers are available automatically:

- **Context7** - Latest library documentation
- **Sequential Thinking** - Multi-step reasoning
- **Memory** - Persistent knowledge graphs
- **GitHub** - Repository operations
- **Brave Search** - Current information

No manual activation needed - Claude selects appropriate tools per request.

---

## Customization

### Project-Specific Overrides

Create `CLAUDE.md` in your project root:

```markdown
# My Project

Stack: Next.js 16, Prisma 7, PostgreSQL
Conventions: 2-space indent, async/await only
Constraints: No class components, hooks only
```

Claude Supercharger will merge project rules with global config.

### Adding Custom Anti-Patterns

Edit `~/.claude/shared/anti-patterns.yml`:

```yaml
custom:
  my_pattern:
    bad: "use legacy API"
    fix: "Use v2 API endpoint (see docs/migration.md)"
```

---

## Architecture

### Execution Flow (Complex Requests)

```
1. Anti-Pattern Detection → Scan 35 patterns
2. Ambiguity Resolution   → Detect unclear elements
3. Intent Extraction      → 9-dimension analysis, max 3 questions
4. Session Awareness      → Track implicit context
5. Memory Block           → Prepend explicit context if multi-turn
6. Execute Task           → Use appropriate tools
7. Pre-Delivery Verify    → 10-point quality gate
8. Output Lock            → Deliverable + optimization note
```

**Simple requests skip to step 6.**

### File Structure

```
~/.claude/
├── CLAUDE.md              # Global base config
├── RULES.md               # v1.0.0 Ops rules + Prompt Master
├── MCP.md                 # v1.0.0 MCP routing + Tool optimization
├── PERSONAS.md            # 9 cognitive archetypes
└── shared/
    └── anti-patterns.yml  # 35 credit-killing patterns
```

---


## Initial Release v1.0.0

**Prompt Master Integration** (8 novel techniques):

1. **35 Anti-Pattern Library** → Proactive detection before execution
2. **Pre-Delivery Verification** → 6-point quality checklist
3. **Forbidden Techniques Blacklist** → Prevents fabrication-prone methods
4. **Output Lock Discipline** → Reduces ceremonial text by ~40%
5. **Intent Extraction Framework** → Structures requirement gathering
6. **Memory Block Template** → Formalizes session context carry-forward
7. **Tool-Specific Optimization** → Per-model constraints (10+ models)
8. **Success Criteria Extraction** → Converts vague goals to binary pass/fail

---

## Benefits

**For You:**
- Fewer re-prompts (35 patterns auto-corrected)
- Smarter questions (max 3, structured)
- Better first-attempt success (10-point verification)
- Context preservation (Memory Block system)
- Persona specialization (9 archetypes)

**For Teams:**
- Shareable configuration (one repo, many users)
- Consistent coding standards
- Knowledge transfer (patterns documented)
- Onboarding acceleration (install script)

---

## Integrations

### Prompt Master

Full Prompt Master skill integration for generating optimized prompts for 30+ AI tools (ChatGPT, Midjourney, Cursor, Devin, etc.). See `integrations/prompt-master/` for details.

### MCP Servers

- **Context7** → External library documentation
- **Sequential Thinking** → Complex analysis
- **Magic** → UI component generation
- **Puppeteer** → Browser automation

---

## Documentation

- [Quick Start Guide](docs/QUICKSTART.md) - 5-minute setup
- [Architecture](docs/ARCHITECTURE.md) - How it all works
- [Customization](docs/CUSTOMIZATION.md) - Tailoring to your needs
- [Troubleshooting](docs/TROUBLESHOOTING.md) - Common issues
- [Contributing](docs/CONTRIBUTING.md) - How to contribute

---

## Uninstall

```bash
bash uninstall.sh
```

Or manually:

```bash
# Restore backup
cp ~/.claude/backups/YYYYMMDD/*.md ~/.claude/

# Remove Claude Supercharger files
rm ~/.claude/shared/anti-patterns.yml
```

---

## License

MIT License - See [LICENSE](LICENSE) for details

---

## Credits

- Created by [@smrafiz](https://github.com/smrafiz)
- **Core framework** based on [SuperClaude Framework](https://github.com/SuperClaude-Org/SuperClaude_Framework) by SuperClaude-Org (MIT License, © 2024 SuperClaude Framework Contributors)
- **Prompt Master** integration from [nidhinjs/prompt-master](https://github.com/nidhinjs/prompt-master)
- Built for [Claude Code](https://claude.ai/code) by Anthropic

### Components Adapted from SuperClaude Framework

- `core/RULES.md` - Evidence-based rules system, severity notation, operational standards
- Rule priority structure with conflict resolution patterns
- Thinking modes framework and workflow orchestration
- Batch operations and parallelization patterns

---

## Support

- Issues: [GitHub Issues](https://github.com/smrafiz/claude-supercharger/issues)
- Discussions: [GitHub Discussions](https://github.com/smrafiz/claude-supercharger/discussions)

---

**Made with ❤️ for the Claude Code community**
