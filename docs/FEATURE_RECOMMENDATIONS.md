# Claude Supercharger - Feature Recommendations

A comprehensive list of valuable features to add to Claude Supercharger, organized by category and priority.

---

## Project Vision

> "One line install, zero manual setup, genuine value for all Claude Code users."

---

## Current Features (v1.9.3)

### Safety Layer (Enforced)
- ✅ Block `rm -rf /`, `rm -rf ~`, `rm -rf ..`
- ✅ Block `git push --force` to main/master
- ✅ Block credential exposure (AWS keys, GitHub tokens)
- ✅ Block `DROP TABLE`, `chmod 777`, fork bombs
- ✅ Block `curl | bash`, `eval`
- ✅ Block `git reset --hard`, `git checkout .`
- ✅ Block wrong package manager (npm in pnpm project)
- ✅ Block unauthorized persistence (`.bashrc`, `.zshrc`, SSH commands)

### Instructional Layer
- **Token Economy** - Standard / Lean / Minimal tiers
- **Roles** - 8 behavioral profiles (developer, writer, student, data, pm, designer, devops, researcher)
- **Agents** - 9 specialized agents (Detective, Critic, Engineer, Writer, Scientist, Architect, Strategist, Analyst, General)
- **Slash Commands** - /think, /challenge, /refactor, /audit

### MCP Servers (Auto-Included)
- Context7 (documentation)
- Sequential Thinking (reasoning)
- Memory (persistent sessions)
- Playwright (browser automation - dev role)
- Magic UI (component library - dev/designer)
- DuckDuckGo (search - writer/student/pm/researcher)

---

## 🎯 PRIORITY RECOMMENDATIONS

### Phase 1: Quick Wins (Low Effort, High Value)

| Feature | What It Does | Auto-Install? | Why Valuable |
|---------|--------------|---------------|--------------|
| **Git Enhanced Hooks** | Block force pushes, require commit messages, prevent commit without tests | ✅ Yes | Everyone uses git |
| **Auto-Lint on Save** | Run ESLint/Prettier after every file edit | ✅ Yes (dev role) | Keeps code clean |
| **File Template Hooks** | Auto-scaffold new files from templates | ✅ Project-level | Saves boilerplate |
| **Context Backup** | Save conversation before compaction | ✅ Full mode | Never lose context |
| **Import Organizer** | Auto-add/remove imports | ✅ Yes | No more unused imports |
| **Add `/test` command** | Generate unit tests for selected code | ✅ Full mode | Huge time saver |
| **Add GitHub MCP** | Issues, PRs, repos, code search | ✅ Yes (dev role) | Popular request |
| **Add PostgreSQL MCP** | Database queries | ❌ Opt-in | Very popular for devs |
| **Commit Message Enforcement** | Require conventional commits | ✅ Opt-in | Better history |

### Phase 2: High Value (Medium Effort)

| Feature | What It Does | Auto-Install? | Why Valuable |
|---------|--------------|---------------|--------------|
| **PostgreSQL MCP** | Query databases directly | ❌ Opt-in | Very popular |
| **Supabase MCP** | Database + Auth + Edge Functions | ❌ Opt-in | Full-stack devs |
| **Figma MCP** | Read designs, export assets | ❌ Opt-in | Designers need this |
| **Slack/Teams MCP** | Send notifications, read channels | ❌ Opt-in | Team workflows |
| **Test Generator** | Auto-generate unit tests from code | ✅ Full mode | Huge time saver |
| **Smart File Templates** | Auto-detect file type, apply template | ✅ Yes | Eliminates boilerplate |
| **Doc Generator** | Auto-generate README, JSDoc | ✅ Yes | Always needed |
| **Security Scanner** | Scan for vulnerabilities | ✅ Opt-in | Important |

### Phase 3: Future (Experimental)

| Feature | What It Does | Why Valuable |
|---------|--------------|--------------|
| **AI Code Review** | Auto-review on commit (LLM-based) | Professional quality |
| **Smart Context Loading** | Auto-detect and load relevant docs | Less manual context |
| **Project Health Dashboard** | Show code health metrics | Visibility |
| **Multi-Model Routing** | Route to different models based on task | Cost optimization |

---

## 🚀 SLASH COMMANDS TO ADD

### Currently in Supercharger:
- `/think` - Structured reasoning
- `/challenge` - Adversarial testing
- `/refactor` - Code quality sweep
- `/audit` - Consistency check

### Recommended Additions:

| Command | What It Does | Auto-Install? |
|---------|--------------|---------------|
| `/test` | Generate unit tests for selected code | ✅ Full mode |
| `/doc` | Auto-generate README, JSDoc, comments | ✅ Yes |
| `/explain` | Explain code in plain language | ✅ Yes |
| `/migrate` | Upgrade deprecated patterns | ✅ Full mode |
| `/security` | Scan for vulnerabilities | ✅ Opt-in |
| `/optimize` | Performance suggestions | ✅ Opt-in |
| `/review` | Full code review with report | ✅ Opt-in |
| `/scaffold` | Create file from template | ✅ Yes |
| `/git pr` | Create PR, run checks, post link | ✅ Yes |
| `/deploy` | Run deploy sequence (customizable) | ✅ Opt-in |

---

## 🔗 ADDITIONAL MCP SERVERS

### Must-Have (Add to Auto-Include):
| MCP Server | What It Does | Value Level |
|------------|--------------|-------------|
| **Filesystem** | File operations, read/write/glob | Must-have |
| **GitHub** | Issues, PRs, repos, code search | Must-have |
| **Brave Search** | Web search | Must-have |

### High Value (Add to Opt-in):
| MCP Server | What It Does | Value Level |
|------------|--------------|-------------|
| **PostgreSQL** | Database queries | High |
| **Supabase** | DB + Auth + Edge Functions | High |
| **Slack** | Send/read messages | Medium |
| **Notion** | Read/write pages | Medium |
| **Sentry** | Error monitoring | Medium |
| **Figma** | Design access | Medium (design) |

### Nice to Have:
| MCP Server | What It Does |
|------------|--------------|
| **Google Drive** | File access |
| **Puppeteer** | Browser scraping |
| **Sequential Thinking** | Reasoning enhancement (already included) |
| **Memory** | Cross-session memory (already included) |

---

## ⚡ HOOK AUTOMATIONS TO ADD

### Safety Hooks (Already Implemented):
- ✅ rm -rf blocking
- ✅ git push --force blocking
- ✅ Credential detection
- ✅ chmod 777 blocking
- ✅ DROP TABLE blocking

### New Hooks to Add:

| Hook | When It Runs | Value |
|------|--------------|-------|
| **Auto-format** | PostToolUse (Edit/Write) | High |
| **Auto-lint** | PostToolUse | High |
| **Auto-test** | PostToolUse (dev files) | High |
| **Commit-check** | PreToolUse (git commit) | High |
| **Prettier** | PostToolUse (code files) | High |
| **ESLint fix** | PostToolUse (JS/TS) | Medium |
| **Import-sort** | PostToolUse (Python/JS) | Medium |
| **Schema-validate** | PostToolUse (JSON/YAML) | Medium |
| **Type-check** | PostToolUse (TS) | High |
| **Secret-scan** | PostToolUse (Write) | High |
| **License-header** | PostToolUse (new files) | Low |
| **Conventional-commit** | PreToolUse (git commit) | High |

---

## 🎯 AGENTS TO ADD

### Currently in Supercharger:
- Detective (debugger)
- Critic (reviewer)
- Engineer (builder)
- Writer (prose)
- Scientist (researcher)
- Architect (design)
- Strategist (planning)
- Analyst (data)
- General (everyday tasks)

### Recommended Additions:

| Agent | What It Does | Best For |
|-------|--------------|----------|
| **Migrations** | DB migrations, schema changes | Backend |
| **Security** | Vulnerability scanning | All |
| **Performance** | Profiling, optimization | Devs |
| **Accessibility** | a11y audits | Frontend |
| **Docs** | Documentation generator | All |
| **Tests** | Test generation | Devs |
| **Refactor** | Pattern upgrades | Devs |
| **DevOps** | Deploy, infra, Docker | DevOps |

---

## 🧠 INTELLIGENT AUTOMATION

| Feature | What It Does | Auto-Install? |
|---------|--------------|---------------|
| **Smart File Templates** | Auto-apply templates by file type | ✅ Yes |
| **Project Type Detection** | Detect React/Node/Python and configure | ✅ Yes |
| **Auto-Import Resolution** | Auto-add missing imports | ✅ Full |
| **Context-Aware Suggestions** | Load relevant docs based on current task | ✅ Full |
| **Pattern Detection** | Detect and fix anti-patterns | ✅ Full |
| **Semantic Search** | Find code by meaning, not just text | ✅ Opt-in |
| **Smart Rename** | Rename with all references | ✅ Opt-in |

---

## 📊 MONITORING & VISIBILITY

| Feature | What It Does | Auto-Install? |
|---------|--------------|---------------|
| **Token Usage** | Real-time token counter | ✅ Yes |
| **Cost Tracking** | Session cost estimation | ✅ Yes |
| **Context Pressure** | 60%/80%/90% warnings | ✅ Yes |
| **Session Timeline** | Show what was done in session | ✅ Full |
| **Code Coverage** | Track test coverage | ✅ Opt-in |
| **Performance Metrics** | Show slow commands | ✅ Opt-in |
| **Activity Log** | Full audit trail | ✅ Yes |

---

## 🔄 WORKFLOW AUTOMATION

| Feature | What It Does | Auto-Install? |
|---------|--------------|---------------|
| **One-Command Deploy** | Build + test + deploy sequence | ✅ Opt-in |
| **Auto-PR** | Create PR with description | ✅ Yes |
| **Branch Cleanup** | Auto-delete merged branches | ✅ Opt-in |
| **Version Bump** | Auto-increment versions | ✅ Opt-in |
| **Changelog Gen** | Auto-generate changelog | ✅ Opt-in |
| **Release Notes** | Generate release notes | ✅ Opt-in |

---

## 🛠️ PROJECT-SPECIFIC AUTOMATION

| Feature | What It Does | Auto-Install? |
|---------|--------------|---------------|
| **Framework Detection** | Detect Next.js/React/Vue/Django | ✅ Yes |
| **Config Generator** | Auto-generate configs | ✅ Yes |
| **Env Validator** | Check .env completeness | ✅ Yes |
| **Package Manager Enforce** | Prevent npm in pnpm projects | ✅ Yes |
| **Docker Helper** | Container commands | ✅ Opt-in |
| **K8s Helper** | Kubernetes commands | ✅ Opt-in |
| **CI/CD Helper** | GitHub Actions / GitLab CI | ✅ Opt-in |

---

## 📋 QUICK-IMPLEMENTATION CHECKLIST

### High Priority (Do First):
- [ ] Add `/test` command
- [ ] Add GitHub MCP to auto-install
- [ ] Add PostgreSQL MCP to opt-in list
- [ ] Add auto-format hook
- [ ] Add commit message checker hook
- [ ] Add Supabase MCP to opt-in

### Medium Priority:
- [ ] Add `/doc` command
- [ ] Add `/security` command
- [ ] Add `/review` command
- [ ] Add smart file templates
- [ ] Add test-on-commit hook
- [ ] Add secret-scanning hook
- [ ] Add Figma MCP to opt-in

### Nice to Have:
- [ ] Add `/scaffold` command
- [ ] Add `/deploy` command
- [ ] Add Docker helper tools
- [ ] Add K8s helper tools

---

## 📚 REFERENCE LINKS

- [Claude Code Hooks Documentation](https://code.claude.com/docs/en/hooks)
- [Best MCP Servers 2026](https://explainmcp.com/mcp-servers/best-mcp-servers-2026/)
- [Custom Slash Commands Guide](https://www.reddit.com/r/ClaudeAI/comments/1or0idm/15_custom_slash_commands_turned_claude_code_into/)
- [Claude Code Skills Guide](https://claudelab.net/en/articles/claude-code/claude-code-custom-skills-development-guide)

---

## 🎯 Vision Reminder

> "One line install, zero manual setup, genuine value for all."

Every feature added should maintain:
1. **Zero manual setup** - Works out of the box
2. **One line install** - No complex configuration
3. **Genuine value** - Not just fluff, but real utility

---

*Last updated: April 2026*
*Claude Supercharger v1.9.3*