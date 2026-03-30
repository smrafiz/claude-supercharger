# MCP Server Setup Guide

Complete guide for installing and configuring Model Context Protocol (MCP) servers with Claude Supercharger.

---

## Table of Contents

1. [Quick Start](#quick-start)
2. [What is MCP?](#what-is-mcp)
3. [Recommended Server Stack](#recommended-server-stack)
4. [API Key Setup](#api-key-setup)
5. [Manual Configuration](#manual-configuration)
6. [Server Details](#server-details)
7. [Usage Examples](#usage-examples)
8. [Troubleshooting](#troubleshooting)

---

## Quick Start

```bash
cd claude-supercharger
bash mcp-setup.sh
```

Follow the interactive prompts to install your desired server tier.

---

## What is MCP?

**Model Context Protocol (MCP)** is an open standard introduced by Anthropic in 2024 for connecting AI models to external tools, databases, and services.

**Benefits:**
- Standardized integration across AI tools
- Secure, sandboxed tool execution
- Real-time data access
- Extensible ecosystem (1,000+ servers as of 2026)

**Supported in:**
- Claude Desktop
- Claude.ai (Pro subscribers)
- Claude API
- Cursor, Windsurf, Zed, Sourcegraph Cody

---

## Recommended Server Stack

### Tier 1 - Must-Have (Core Enhancement)

| Server | Purpose | API Key | Installation |
|--------|---------|---------|--------------|
| **Context7** | Latest version-specific docs (React, Next.js, Tailwind, Prisma, etc.) | ✅ Required | [Get key →](#context7) |
| **Sequential Thinking** | Multi-step reasoning, complex problem solving | ❌ None | Auto |
| **Memory** | Knowledge graphs, persistent session memory | ❌ None | Auto |

**Impact:** Transforms Claude from reactive to context-aware with documentation lookup and structured reasoning.

---

### Tier 2 - Highly Useful (Productivity)

| Server | Purpose | API Key | Installation |
|--------|---------|---------|--------------|
| **GitHub** | Repo operations, PRs, issues | ✅ Token | [Get token →](#github) |
| **Brave Search** | Current information, web research | ✅ Required | [Get key →](#brave-search) |
| **Filesystem** | Secure file operations | ❌ None | Auto |

**Impact:** Adds version control integration, real-time information, and enhanced file management.

---

### Tier 3 - Specialized (Advanced)

| Server | Purpose | API Key | Installation |
|--------|---------|---------|--------------|
| **Playwright** | Browser automation, cross-browser testing | ❌ None | Auto |
| **Puppeteer** | Chrome automation (lighter than Playwright) | ❌ None | Auto |
| **Prisma** | Database operations, schema migrations | ❌ None | Requires Prisma CLI |
| **Neon** | Serverless Postgres, natural language DB | ✅ Connection string | [Get string →](#neon) |
| **Magic UI** | React + Tailwind component library | ❌ None | Auto |
| **Slack** | Team communication, thread context | ✅ Bot token | [Get token →](#slack) |

**Impact:** Specialized workflows for database, UI generation, browser automation, team collaboration.

---

## API Key Setup

### Context7

**What it does:** Fetches latest version-specific documentation for 50+ libraries.

**Get API key:**
1. Visit [https://context.ai](https://context.ai)
2. Sign up for free account
3. Navigate to API Keys section
4. Create new API key
5. Copy key (starts with `ctx_`)

**Free tier:** 1,000 queries/month

---

### GitHub

**What it does:** Repository operations, PR creation, issue management.

**Get Personal Access Token:**
1. Visit [https://github.com/settings/tokens](https://github.com/settings/tokens)
2. Click "Generate new token" → "Generate new token (classic)"
3. Select scopes:
   - `repo` (full control of private repositories)
   - `workflow` (update GitHub Action workflows)
   - `read:org` (read org and team membership)
4. Generate and copy token (starts with `ghp_`)

**Permissions:** Free for public repos, works with private repos too.

---

### Brave Search

**What it does:** Web search for current information beyond Claude's knowledge cutoff.

**Get API key:**
1. Visit [https://brave.com/search/api/](https://brave.com/search/api/)
2. Sign up for API access
3. Choose plan:
   - **Free tier:** 2,000 queries/month
   - **Pro:** $5/month for 20,000 queries
4. Copy API key from dashboard

---

### Neon

**What it does:** Serverless Postgres with natural language interactions.

**Get connection string:**
1. Visit [https://neon.tech](https://neon.tech)
2. Sign up for free account
3. Create new project
4. Navigate to "Connection Details"
5. Copy connection string (format: `postgresql://user:pass@host/db`)

**Free tier:** 512 MB storage, 1 project

---

### Slack

**What it does:** Read threads, post messages, access team context.

**Get Bot Token:**
1. Visit [https://api.slack.com/apps](https://api.slack.com/apps)
2. Click "Create New App" → "From scratch"
3. Name app and select workspace
4. Navigate to "OAuth & Permissions"
5. Add Bot Token Scopes:
   - `channels:history`
   - `channels:read`
   - `chat:write`
   - `users:read`
6. Install app to workspace
7. Copy "Bot User OAuth Token" (starts with `xoxb-`)

**Permissions:** Free for all Slack workspaces.

---

## Manual Configuration

If you prefer manual setup or `mcp-setup.sh` fails, edit `~/.claude/claude_desktop_config.json` directly.

### Configuration File Location

```
~/.claude/claude_desktop_config.json
```

### Basic Structure

```json
{
  "mcpServers": {
    "server-name": {
      "command": "npx",
      "args": ["-y", "@package/name"],
      "env": {
        "API_KEY": "your_key_here"
      }
    }
  }
}
```

---

### Manual Server Configurations

#### Context7

```json
{
  "mcpServers": {
    "context7": {
      "command": "npx",
      "args": ["-y", "@upstash/context7-mcp"],
      "env": {
        "CONTEXT7_API_KEY": "ctx_your_api_key_here"
      }
    }
  }
}
```

---

#### Sequential Thinking

```json
{
  "mcpServers": {
    "sequential-thinking": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-sequential-thinking"]
    }
  }
}
```

---

#### Memory

```json
{
  "mcpServers": {
    "memory": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-memory"]
    }
  }
}
```

---

#### GitHub

```json
{
  "mcpServers": {
    "github": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-github"],
      "env": {
        "GITHUB_PERSONAL_ACCESS_TOKEN": "ghp_your_token_here"
      }
    }
  }
}
```

---

#### Brave Search

```json
{
  "mcpServers": {
    "brave-search": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-brave-search"],
      "env": {
        "BRAVE_API_KEY": "your_brave_api_key_here"
      }
    }
  }
}
```

---

#### Filesystem

```json
{
  "mcpServers": {
    "filesystem": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-filesystem", "/Users/yourname"]
    }
  }
}
```

**Note:** Replace `/Users/yourname` with your allowed directory path.

---

#### Playwright

```json
{
  "mcpServers": {
    "playwright": {
      "command": "npx",
      "args": ["-y", "@executeautomation/playwright-mcp-server"]
    }
  }
}
```

---

#### Puppeteer

```json
{
  "mcpServers": {
    "puppeteer": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-puppeteer"]
    }
  }
}
```

---

#### Prisma

```json
{
  "mcpServers": {
    "prisma": {
      "command": "npx",
      "args": ["prisma", "mcp"]
    }
  }
}
```

**Requirements:** Prisma CLI must be installed in your project.

---

#### Neon

```json
{
  "mcpServers": {
    "neon": {
      "command": "npx",
      "args": ["-y", "@neondatabase/mcp-server-neon"],
      "env": {
        "DATABASE_URL": "postgresql://user:pass@host/db"
      }
    }
  }
}
```

---

#### Magic UI

```json
{
  "mcpServers": {
    "magic-ui": {
      "command": "npx",
      "args": ["-y", "@magicuidesign/mcp-server-magicui"]
    }
  }
}
```

---

#### Slack

```json
{
  "mcpServers": {
    "slack": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-slack"],
      "env": {
        "SLACK_BOT_TOKEN": "xoxb-your-token-here"
      }
    }
  }
}
```

---

## Server Details

### Context7 (Most Popular in 2026)

**Capabilities:**
- Fetches latest docs for React, Next.js, Tailwind, Prisma, TypeScript, Vue, Svelte, etc.
- Version-specific (e.g., React 19 vs React 18)
- Auto-updates when libraries release new versions
- Injects documentation directly into Claude's context

**Use cases:**
- "How do I use React Server Components in Next.js 15?"
- "Show me Tailwind 4 container queries syntax"
- "Prisma 7 migration best practices"

**Token usage:** Medium (fetches only relevant sections)

---

### Sequential Thinking

**Capabilities:**
- Multi-step reasoning framework
- Thought chain decomposition
- Branching and revision support
- Traceable problem-solving

**Use cases:**
- Complex architecture design
- Algorithm optimization
- Debugging multi-layer issues
- Refactoring strategies

**Token usage:** High (generates extensive reasoning chains)

**Unique:** Only tool with no CLI alternative—pure reasoning enhancement.

---

### Memory

**Capabilities:**
- Knowledge graph storage
- Cross-session persistence
- Fact relationships
- User preference tracking

**Use cases:**
- "Remember: I prefer functional components over classes"
- "What did we decide about authentication?"
- "Recall the API structure we designed last week"

**Token usage:** Low (efficient graph queries)

**Storage:** Local filesystem (`~/.claude/memory/`)

---

### GitHub

**Capabilities:**
- Repository search and clone
- PR creation and management
- Issue tracking
- Code review
- Branch operations

**Use cases:**
- "Create a PR for the feature branch"
- "Search for authentication-related issues"
- "Show me recent commits on main"

**Token usage:** Low (metadata only)

---

### Brave Search

**Capabilities:**
- Web search beyond training cutoff
- News and current events
- Documentation lookup
- Research queries

**Use cases:**
- "What are the latest security vulnerabilities in React?"
- "Search for Next.js 16 release notes"
- "Find tutorials on WebGPU"

**Token usage:** Medium (returns search snippets)

---

### Filesystem

**Capabilities:**
- Read/write files
- Directory operations
- File search
- Sandboxed access

**Use cases:**
- "Read all TypeScript files in src/"
- "Create a new component at src/components/Button.tsx"
- "Find all files importing useState"

**Token usage:** Variable (depends on file size)

**Security:** Restricted to allowed directories only.

---

### Playwright

**Capabilities:**
- Browser automation (Chrome, Firefox, Safari, Edge)
- Screenshot capture
- Element interaction
- Accessibility tree navigation
- Localhost testing

**Use cases:**
- "Test the login flow on localhost:3000"
- "Screenshot the dashboard at different screen sizes"
- "Click the submit button and verify the success message"

**Token usage:** High (accessibility trees are large)

---

### Puppeteer

**Capabilities:**
- Chrome/Chromium automation
- Screenshot and PDF generation
- Performance metrics
- Network interception

**Use cases:**
- "Screenshot the homepage"
- "Generate PDF of the documentation"
- "Measure page load time"

**Token usage:** High

**vs Playwright:** Lighter, faster startup, Chrome-only.

---

### Prisma

**Capabilities:**
- Database schema inspection
- Query execution
- Migration management
- Type generation

**Use cases:**
- "Show me the User model schema"
- "Run a query to find all active users"
- "Create a migration for the new field"

**Token usage:** Low (SQL and schema)

**Requirements:** Must run in project with `prisma/schema.prisma`.

---

### Neon

**Capabilities:**
- Natural language database queries
- Branch management (database branching)
- Schema inspection
- Serverless Postgres operations

**Use cases:**
- "Create a database branch for testing"
- "Show me the users table schema"
- "Query all orders from last month"

**Token usage:** Low

---

### Magic UI

**Capabilities:**
- React + Tailwind component generation
- Production-ready JSX
- Animations and effects
- Component library access

**Use cases:**
- "Add a marquee animation for logos"
- "Create a blur fade text effect"
- "Generate a gradient button component"

**Token usage:** Low (returns component code)

---

### Slack

**Capabilities:**
- Read channel history
- Post messages
- Thread context retrieval
- User lookup

**Use cases:**
- "Fetch context from #engineering thread about auth"
- "Post deployment update to #releases"
- "Find all mentions of 'database migration'"

**Token usage:** Medium (thread history)

---

## Usage Examples

### Example 1: Context-Aware Development

**Request:**
```
"Create a React Server Component that fetches user data using the latest Next.js 15 patterns"
```

**What happens:**
1. Context7 fetches Next.js 15 Server Component docs
2. Claude generates component with correct syntax
3. Memory stores your preference for Server Components

---

### Example 2: Complex Problem Solving

**Request:**
```
"Design a scalable authentication system with JWT refresh tokens, considering security, performance, and user experience"
```

**What happens:**
1. Sequential Thinking breaks down into steps:
   - Security requirements analysis
   - Token rotation strategy
   - Storage considerations
   - Performance optimization
   - UX flow design
2. Each step is traceable and can be revised
3. Final solution with reasoning chain

---

### Example 3: Cross-Tool Workflow

**Request:**
```
"Search for Next.js 16 breaking changes, update my repository, create a PR, and remember what changed"
```

**What happens:**
1. Brave Search finds release notes
2. GitHub clones repo
3. Filesystem edits files
4. GitHub creates PR
5. Memory stores migration notes

---

## Troubleshooting

### MCP Servers Not Appearing

**Symptoms:** No MCP icon in Claude Desktop.

**Solutions:**
1. Completely quit Claude Desktop (not just close window)
2. Restart Claude Desktop
3. Check config file syntax: `cat ~/.claude/claude_desktop_config.json`
4. Validate JSON: `python3 -m json.tool ~/.claude/claude_desktop_config.json`

---

### API Key Errors

**Symptoms:** Server fails with authentication error.

**Solutions:**
1. Verify key format (Context7: `ctx_`, GitHub: `ghp_`, Slack: `xoxb-`)
2. Check key hasn't expired
3. Verify permissions/scopes
4. Test key with provider's API directly

---

### Server Crashes on Startup

**Symptoms:** Server listed but tools not available.

**Solutions:**
1. Check Node.js version: `node --version` (requires v18+)
2. Clear npm cache: `npm cache clean --force`
3. Check server logs: Claude Desktop → Help → View Logs
4. Try manual installation: `npx -y @package/name`

---

### High Token Usage

**Symptoms:** Context window fills quickly.

**Solutions:**
1. Use Context7 selectively (not every query)
2. Limit Playwright to specific pages
3. Use Puppeteer instead of Playwright for simple tasks
4. Configure Sequential Thinking depth limits
5. Memory: prune old entries periodically

---

### Filesystem Permission Denied

**Symptoms:** Cannot read/write files.

**Solutions:**
1. Check allowed directory in config
2. Ensure Claude Desktop has filesystem permissions (macOS: System Preferences → Privacy)
3. Use absolute paths: `/Users/name/project` not `~/project`

---

### GitHub Rate Limiting

**Symptoms:** "API rate limit exceeded" errors.

**Solutions:**
1. Use authenticated token (not anonymous)
2. Token with proper scopes increases rate limit
3. GitHub Free: 5,000 requests/hour
4. Batch operations when possible

---

### Prisma Not Found

**Symptoms:** "Prisma CLI not found" error.

**Solutions:**
1. Ensure Prisma is installed: `npx prisma --version`
2. Run from project directory with `package.json`
3. Install Prisma: `npm install -D prisma`

---

### Neon Connection Fails

**Symptoms:** Database connection timeout.

**Solutions:**
1. Verify connection string format
2. Check database is not paused (Neon auto-pauses inactive DBs)
3. Test connection: `psql "postgresql://..."`
4. Ensure IP allowlist includes your IP (if configured)

---

## Best Practices

1. **Start with Tier 1** - Core enhancement without overwhelming complexity
2. **API key security** - Never commit keys to version control
3. **Token budgets** - Monitor context usage with multiple servers
4. **Server selection** - Claude auto-selects appropriate servers per request
5. **Backup config** - Save `claude_desktop_config.json` before changes
6. **Update regularly** - MCP servers update frequently via `npx -y`
7. **Test incrementally** - Add one server at a time to isolate issues

---

## Uninstall MCP Servers

### Remove specific server

Edit `~/.claude/claude_desktop_config.json` and delete the server entry.

### Remove all servers

```bash
rm ~/.claude/claude_desktop_config.json
```

### Restore backup

```bash
cp ~/.claude/claude_desktop_config.backup.TIMESTAMP.json ~/.claude/claude_desktop_config.json
```

---

## Resources

- **Official MCP Docs:** [https://modelcontextprotocol.io](https://modelcontextprotocol.io)
- **Server Directory:** [https://mcpservers.org](https://mcpservers.org)
- **Awesome MCP Servers:** [https://github.com/appcypher/awesome-mcp-servers](https://github.com/appcypher/awesome-mcp-servers)
- **Context7:** [https://context.ai](https://context.ai)
- **Claude Desktop:** [https://claude.ai/download](https://claude.ai/download)

---

*Claude Supercharger v1.0.0 | MCP ecosystem integration guide*
