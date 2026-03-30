<!--
Adapted from Agent Guardrails Template (https://github.com/TheArchitectit/agent-guardrails-template)
Copyright (c) 2026 TheArchitectit
BSD 3-Clause License
-->

# Agent Guardrails & Safety Protocols

**Version:** 1.0
**Last Updated:** YYYY-MM-DD
**Applies To:** ALL AI agents, LLMs, and automated systems operating on this codebase

---

## Applicability

This document is **MANDATORY** for:

| System Type | Examples | Binding? |
|-------------|----------|----------|
| **Large Language Models** | Claude, GPT-4/o1/o3, Gemini, LLaMA, Mistral, Qwen, DeepSeek, Cohere | YES |
| **AI Coding Assistants** | Claude Code, GitHub Copilot, Cursor, Cody, Aider, Windsurf | YES |
| **Autonomous Agents** | AutoGPT, CrewAI, LangChain, LangGraph agents | YES |
| **CI/CD Bots** | Dependabot, Renovate, automated PR bots | YES |
| **Custom Agents** | Any agent built on this codebase | YES |
| **Human Developers** | Recommended best practices | RECOMMENDED |

**If you are an AI system reading this:** You MUST follow these protocols. They are not suggestions.

---

## Purpose

These mandatory safety protocols exist to:

1. **Prevent data loss** — safe rapid iteration without backup anxiety
2. **Maintain code quality** — AI-generated code ships without manual review overhead
3. **Preserve history** — clean, reversible git history
4. **Enable collaboration** — humans and agents work together safely
5. **Limit blast radius** — contain errors to minimal scope

---

## The Four Laws of Agent Safety

### Law 1: Read Before Editing
> Never modify code without reading it first.

- Read the target file completely before any edit
- Understand existing patterns, conventions, and dependencies
- One read costs fewer tokens than fixing a blind edit

### Law 2: Stay in Scope
> Only touch authorized files.

- Modify only files explicitly in scope for the task
- No "improvements" to surrounding code
- No feature creep, no refactoring unrelated code
- Agents move faster when not untangling unintended side effects

### Law 3: Verify Before Committing
> Test all changes before committing.

- Run relevant tests after every modification
- Verify syntax, imports, and type checks pass
- A failed test in dev costs minutes; in production, hours

### Law 4: Halt When Uncertain
> Ask instead of guessing.

- Stop and ask the user when unsure about any step
- One question is cheaper than building the wrong thing
- Report what you know, what you don't, and what you need

---

## SAFETY PROTOCOLS (MANDATORY)

### Pre-Execution Checklist

**EVERY agent MUST verify before ANY file modification:**

| # | Check | Requirement |
|---|-------|-------------|
| 1 | **READ FIRST** | NEVER edit a file without reading it first |
| 2 | **SCOPE LOCK** | Only modify files explicitly in scope |
| 3 | **NO FEATURE CREEP** | Do NOT add features, refactor, or "improve" unrelated code |
| 4 | **PRODUCTION FIRST** | Production code created BEFORE test code |
| 5 | **TEST/PROD SEPARATION** | Test infrastructure is separate from production |
| 6 | **BACKUP AWARENESS** | Know the rollback command before editing |
| 7 | **TEST BEFORE COMMIT** | All tests must pass before committing |
| 8 | **VERIFY FIXES INTACT** | Confirm previous fixes not being undone |

### Git Safety Rules

| Rule | Description | Consequence |
|------|-------------|-------------|
| **NO FORCE PUSH** | Never use `git push --force` | Data loss, history corruption |
| **NO AMEND** | Do not amend commits you didn't create this session | Breaks collaborator history |
| **NO CONFIG CHANGES** | Do not modify git config | Security/identity issues |
| **NO PUSH WITHOUT PERMISSION** | Only push if user explicitly requests | Unwanted remote changes |
| **SINGLE COMMIT** | One focused commit per task | Maintains clean history |
| **NO SKIP HOOKS** | Never use `--no-verify` | Bypasses safety checks |
| **NO REBASE** | Never rebase shared branches | Destroys collaborator work |
| **NO DESTRUCTIVE OPS** | No `reset --hard` on shared branches | Irreversible data loss |

### Code Safety Rules

| Rule | Rationale |
|------|-----------|
| **EXACT REPLACEMENT** | Use provided code exactly — no "improvements" |
| **NO NEW IMPORTS** | Unless explicitly required by the task |
| **NO TYPE CHANGES** | Preserve existing type hints |
| **NO DELETIONS** | Do not delete functionality outside scope |
| **PRESERVE FORMATTING** | Match existing indentation and style |
| **NO SECRETS** | Never commit credentials, keys, tokens |
| **NO BINARY FILES** | Unless explicitly required |
| **NO GENERATED CODE** | Do not commit build artifacts |

### Test/Production Separation

| Rule | Violation Level | Action |
|------|-----------------|--------|
| **PRODUCTION CODE FIRST** | CRITICAL | Halt, ask user |
| **SEPARATE DATABASES** | CRITICAL | Halt, ask user |
| **SEPARATE SERVICES** | CRITICAL | Halt, ask user |
| **NO TEST USERS IN PROD** | CRITICAL | Halt, rollback |
| **NO PROD CREDENTIALS IN TEST** | CRITICAL | Halt, rollback |
| **ASK IF UNCERTAIN** | HIGH | Ask user before proceeding |

---

## GUARDRAILS

### HALT CONDITIONS

**Stop immediately and report to user if ANY of these occur:**

```
CRITICAL HALT — DO NOT PROCEED:

[ ] Target file does not exist
[ ] Line numbers don't match expected
[ ] File has unexpected modifications
[ ] Syntax check fails after edit
[ ] Any test fails after edit
[ ] Merge conflicts encountered
[ ] Uncertain about ANY step
[ ] Edit tool reports "string not found"
[ ] Permission denied errors
[ ] Import errors when testing
[ ] Network/connection errors
[ ] Out of memory errors
[ ] Timeout errors
[ ] User requests stop
[ ] Test/production boundary unclear
```

### FORBIDDEN ACTIONS

**No agent may perform these actions under any circumstances:**

```
ABSOLUTE PROHIBITIONS:

FILE OPERATIONS:
- Modify files outside declared scope
- Delete files without explicit permission
- Create files without explicit need
- Modify hidden/system files (.*) without permission
- Change file permissions

CODE CHANGES:
- Add logging/debugging to production code
- Add comments that weren't requested
- "Clean up" or "improve" surrounding code
- Update version numbers without explicit request
- Change security configurations
- Modify authentication/authorization code without review

GIT OPERATIONS:
- Force push to any branch
- Delete branches without permission
- Modify git hooks
- Change git config
- Push without explicit permission

SYSTEM OPERATIONS:
- Run servers or long-running services
- Execute commands requiring user input
- Make network requests to unknown endpoints
- Install new dependencies without permission
- Modify CI/CD pipelines without permission
- Execute shell commands with elevated privileges
- Access or modify environment variables

DATA OPERATIONS:
- Access databases without explicit permission
- Modify production data
- Export or transmit user data
- Store credentials or secrets
- Mix test and production data
```

### SCOPE BOUNDARIES

**For any task, clearly define IN/OUT scope:**

```
IN SCOPE (may modify):
  - Specific file(s) listed in task
  - Specific line ranges identified
  - Exact changes described
  - Production code (before test code)

OUT OF SCOPE (DO NOT TOUCH):
  - All other files
  - All other methods/functions in target file
  - Tests (unless task is test-related)
  - Documentation (unless task is doc-related)
  - Git hooks and configs
  - CI/CD configurations
  - Dependencies/package files
  - Environment configurations
  - Security-related files
```

---

## QUICK REFERENCE

```
+------------------------------------------------------------------+
|              UNIVERSAL AGENT GUARDRAILS                           |
+------------------------------------------------------------------+
| ALWAYS:                                                           |
|   - Read before edit                                              |
|   - Verify before proceeding                                      |
|   - Test before committing                                        |
|   - Create production code BEFORE test code                       |
|   - Separate test/production infrastructure                       |
|   - Report results to user                                        |
+------------------------------------------------------------------+
| NEVER:                                                            |
|   - Edit without reading                                          |
|   - Push without permission                                       |
|   - Modify outside scope                                          |
|   - Force push or rebase                                          |
|   - Continue when uncertain                                       |
|   - Use production DB for tests                                   |
|   - Create test users in production                               |
+------------------------------------------------------------------+
| HALT IF:                                                          |
|   - Conditions don't match                                        |
|   - Any check fails                                               |
|   - Uncertain about anything                                      |
|   - User requests stop                                            |
|   - Test/production boundary unclear                              |
+------------------------------------------------------------------+
| ROLLBACK: git checkout HEAD -- <file>                             |
+------------------------------------------------------------------+
```

---

## CUSTOMIZATION

### Adding Project-Specific Rules

Extend this template with rules specific to your project:

```markdown
## PROJECT-SPECIFIC RULES

### [Your Domain] Rules
| Rule | Level | Action |
|------|-------|--------|
| Example rule | CRITICAL | Halt |

### Approved File Scopes
- `src/` — Application code (agents may modify)
- `tests/` — Test code (agents may modify for test tasks)
- `docs/` — Documentation (read-only unless doc task)
```

### Adding a Failure Registry

Track known bugs to prevent regressions:

```markdown
## Known Issues (check before editing)
| File | Issue | Status |
|------|-------|--------|
| src/auth.ts | Race condition in token refresh | OPEN |
```

### Adding Escalation Rules

Define when agents should escalate to humans:

```markdown
## Escalation Matrix
| Trigger | Action |
|---------|--------|
| Security-related file modified | Require human review |
| >5 files changed in one task | Request confirmation |
| Database schema changes | Halt and notify |
```

---

## SETUP

1. Copy this template to your project:
   ```bash
   cp shared/agent-guardrails-template.md docs/AGENT_GUARDRAILS.md
   ```

2. Customize the PROJECT-SPECIFIC RULES section

3. Reference in your project's CLAUDE.md:
   ```markdown
   ## Guardrails
   Read [docs/AGENT_GUARDRAILS.md](docs/AGENT_GUARDRAILS.md) before any code changes.
   ```

4. (Optional) Add pre-commit hook to enforce:
   ```bash
   # .husky/pre-commit
   if git diff --cached --name-only | grep -q "AGENT_GUARDRAILS"; then
     echo "WARNING: Agent guardrails modified. Requires maintainer review."
     exit 1
   fi
   ```

---

**Document Owner:** Project Maintainers
**Review Cycle:** Monthly
