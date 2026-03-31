# Claude Supercharger v1.0 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a role-based, zero-dependency Claude Code configuration kit with 3 install modes, 5 roles, 6 hooks, and 2 tools.

**Architecture:** Shell-only installer copies markdown configs + hook scripts to `~/.claude/`. Modular `lib/` scripts handle backup, roles, hooks, and extras. Python used only for JSON merge operations.

**Tech Stack:** Bash, Python (json module only), Claude Code hooks API

**Spec:** `docs/superpowers/specs/2026-03-31-claude-supercharger-v1-design.md`

---

## File Structure

### Files to CREATE (new)

```
configs/
  universal/
    CLAUDE.md                    # ~50 lines, universal config
    supercharger.md              # ~65 lines, workflow rules
    guardrails.md                # ~40 lines, Four Laws + safety
  roles/
    developer.md                 # Developer role overlay
    writer.md                    # Writer role overlay
    student.md                   # Student role overlay
    data.md                      # Data Analyst role overlay
    pm.md                        # PM role overlay
hooks/
  safety.sh                      # Block destructive commands
  notify.sh                      # Platform-aware notifications
  git-safety.sh                  # Protect git operations
  auto-format.sh                 # Post-edit formatting
  prompt-validator.sh            # Anti-pattern scanning
  compaction-backup.sh           # Pre-compaction transcript save
lib/
  utils.sh                       # Colors, logging, platform detection
  backup.sh                      # Backup/restore functions
  roles.sh                       # Role selection UI + deployment
  hooks.sh                       # Hook assembly + settings.json merge
  extras.sh                      # MCP, guardrails, diagnostic deploy
tools/
  claude-check.sh                # Installation health diagnostic
```

### Files to MODIFY (from existing)

```
install.sh                       # Complete rewrite as thin orchestrator
uninstall.sh                     # Complete rewrite for new architecture
mcp-setup.sh → tools/mcp-setup.sh   # Move + keep existing hardened version
shared/anti-patterns.yml         # Keep as-is (already good)
LICENSE                          # Update for new project scope
README.md                        # Complete rewrite for new project
CHANGELOG.md                     # Rewrite for v1.0
.gitignore                       # Update if needed
```

### Files to REMOVE (old SuperClaude content)

```
core/                            # Entire directory (CLAUDE.md, RULES.md, MCP.md, PERSONAS.md)
docs/GUARDRAILS.md               # Replaced by configs/universal/guardrails.md
docs/MCP_SETUP.md                # Replaced by tools/mcp-setup.sh self-documenting
docs/MIGRATION.md                # No longer relevant
docs/QUICKSTART.md               # Replaced by README.md
examples/                        # Entire directory (guardrails examples)
integrations/                    # Entire directory (prompt-master)
merge.sh                         # No longer needed
shared/guardrails-template.yml   # Replaced by configs/universal/guardrails.md
shared/agent-guardrails-template.md  # Content distilled into guardrails.md
```

---

## Task 1: Clean Up — Remove Old SuperClaude Content

**Files:**
- Remove: `core/`, `examples/`, `integrations/`, `docs/GUARDRAILS.md`, `docs/MCP_SETUP.md`, `docs/MIGRATION.md`, `docs/QUICKSTART.md`, `merge.sh`, `shared/guardrails-template.yml`, `shared/agent-guardrails-template.md`
- Keep: `shared/anti-patterns.yml`, `mcp-setup.sh` (will move later), `install.sh` (will rewrite), `uninstall.sh` (will rewrite), `LICENSE`, `README.md`, `CHANGELOG.md`, `.gitignore`

- [ ] **Step 1: Remove old directories and files**

```bash
git rm -r core/
git rm -r examples/
git rm -r integrations/
git rm docs/GUARDRAILS.md docs/MCP_SETUP.md docs/MIGRATION.md docs/QUICKSTART.md
git rm merge.sh
git rm shared/guardrails-template.yml shared/agent-guardrails-template.md
```

- [ ] **Step 2: Move mcp-setup.sh to tools/**

```bash
mkdir -p tools
git mv mcp-setup.sh tools/mcp-setup.sh
```

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "chore: remove SuperClaude content, prepare for v1.0 architecture"
```

---

## Task 2: Create Directory Structure

**Files:**
- Create: `configs/universal/`, `configs/roles/`, `hooks/`, `lib/`, `tools/`

- [ ] **Step 1: Create all directories**

```bash
mkdir -p configs/universal
mkdir -p configs/roles
mkdir -p hooks
mkdir -p lib
```

(`tools/` already exists from Task 1)

- [ ] **Step 2: Add .gitkeep to empty dirs (temporary)**

```bash
touch configs/universal/.gitkeep
touch configs/roles/.gitkeep
touch hooks/.gitkeep
touch lib/.gitkeep
```

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "chore: create v1.0 directory structure"
```

---

## Task 3: Write Universal Configs

**Files:**
- Create: `configs/universal/CLAUDE.md`
- Create: `configs/universal/supercharger.md`
- Create: `configs/universal/guardrails.md`

- [ ] **Step 1: Write `configs/universal/CLAUDE.md`**

Content from spec Section 6. The `{{ROLES}}` and `{{MODE}}` placeholders will be replaced by the installer at deploy time using `sed`.

```markdown
# Claude Supercharger v1.0

## Your Environment
- Roles: {{ROLES}}
- Install mode: {{MODE}}

## Response Principles
- Lead with the answer or action, then explain only if asked
- When uncertain, say so — never fabricate sources, commands, or APIs
- Match response length to question complexity
- Use the user's terminology, not yours

## Verification Gate
Before claiming any task is complete:
- Run the relevant check (test, build, lint) and confirm it passes
- Never say "should work" or "looks correct" without evidence
- If you cannot verify, say what the user should check

## Safety Boundaries
- Never run destructive commands (rm -rf, DROP TABLE, git push --force)
- Never commit secrets, credentials, or API keys
- Never modify files outside the project directory without asking
- If a request seems risky, explain the risk and ask for confirmation

## Anti-Patterns to Avoid
- No ceremonial text ("I'll now proceed to...")
- No unrequested refactoring or scope expansion
- No hallucinated libraries, functions, or flags
- No repeating back what the user just said
- Maximum 3 clarifying questions before proceeding

## Context Management
- When context exceeds 60%, proactively suggest /compact
- Preserve key decisions and constraints through compaction
- For multi-turn tasks, track what was decided and what failed

## Getting Best Results
For complex requests, include:
- Scope: which files/sections to touch (and what NOT to touch)
- Context: what exists now, what you want changed
- Constraints: requirements that must not be broken
```

- [ ] **Step 2: Write `configs/universal/supercharger.md`**

Content from spec Section 7. Exact content as specified.

```markdown
# Supercharger Rules
# Inspired by SuperClaude Framework (MIT) — distilled for brevity

## Execution Workflow
For complex requests, follow this sequence:
1. Scan request for ambiguity — if vague, ask (max 3 questions)
2. Plan steps before acting — state what you'll do, then do it
3. Execute with appropriate tools
4. Verify output before claiming done
Simple requests: skip to step 3.

## Anti-Pattern Detection
Before executing, scan for these patterns and fix silently:
- Vague verbs ("fix it", "make it better") → ask what specifically
- Missing scope ("update the app") → ask which files/functions
- No success criteria → derive a binary pass/fail condition
- Multiple tasks in one request → split and confirm priority

## Forbidden Patterns
Never use these — they degrade output quality:
- Chain of Thought prompting on reasoning models (o3/o4/R1/DeepSeek)
- Fabricated branching ("let me consider 3 approaches" without doing so)
- Simulated parallelism in sequential execution
- Self-consistency checks that contaminate earlier reasoning

## Output Discipline
- Every sentence must be load-bearing — no filler
- Code output: no comments unless asked, no boilerplate
- Deliver the result first, then offer one optimization note if relevant
- Never pad responses with unrequested explanations

## Error Recovery
When something fails:
1. Read the actual error — don't guess
2. Try one focused fix based on the error
3. If that fails, try one alternative approach
4. After 3 attempts, stop and explain what was tried
Never: retry blindly, give up silently, or blame the user

## Context Carry-Forward
For multi-turn tasks (3+ related prompts):
- Track: decisions made, constraints established, what failed
- When referencing prior work, state what you're building on
- If context was compacted, reconstruct key decisions before proceeding

## Scope Discipline
- Only change what was requested — no drive-by refactoring
- If you notice something worth improving, mention it without fixing
- Ask before modifying files outside the explicit scope
- One task at a time, completed fully before starting the next
```

- [ ] **Step 3: Write `configs/universal/guardrails.md`**

Content from spec Section 8. Exact content as specified.

```markdown
# Guardrails — Claude Supercharger
# Inspired by TheArchitectit/agent-guardrails-template (BSD-3)

## Four Laws (Always Active)
1. Read before editing — never modify what you haven't read
2. Stay in scope — only change what was requested
3. Verify before committing — run checks, confirm output
4. Halt when uncertain — ask rather than guess

## Autonomy Levels
- Low risk → proceed (formatting, typos, simple edits)
- Medium risk → state intent, then proceed (new files, refactoring)
- High risk → stop and confirm (deletion, deployment, security)

## When to Stop and Ask
- About to modify a file you haven't read
- Request has multiple valid interpretations
- Change could affect systems beyond current scope
- Three consecutive attempts have failed
- Involves credentials, payments, or compliance
- Unsure about environment (test vs production)

## When Escalating, Report
- What you're trying to do
- What's blocking you
- Options considered with trade-offs
- Recommended action

## Safety (All Roles)
- Never execute destructive commands without confirmation
- Never commit secrets or credentials
- Never modify files outside project scope
- Flag risky operations before executing

## Quality (All Roles)
- Validate output before claiming done
- One task at a time, completed fully
- If something breaks, fix it before moving on
```

- [ ] **Step 4: Remove .gitkeep from configs/universal/**

```bash
rm configs/universal/.gitkeep
```

- [ ] **Step 5: Verify files**

```bash
wc -l configs/universal/*.md
# Expected: CLAUDE.md ~45, supercharger.md ~55, guardrails.md ~40
```

- [ ] **Step 6: Commit**

```bash
git add configs/universal/
git commit -m "feat: add universal configs (CLAUDE.md, supercharger rules, guardrails)"
```

---

## Task 4: Write Role Overlays

**Files:**
- Create: `configs/roles/developer.md`
- Create: `configs/roles/writer.md`
- Create: `configs/roles/student.md`
- Create: `configs/roles/data.md`
- Create: `configs/roles/pm.md`

- [ ] **Step 1: Write `configs/roles/developer.md`**

Content from spec Section 9, Developer role. Exact content as specified.

```markdown
# Role: Developer

## Code Output
- Code only, no explanations unless asked
- Prefer: destructuring, arrow functions, ternary, chaining
- Short variable names in small scopes, descriptive in large ones
- No TODO comments, no console.log, no debug code in output

## Workflow
- Read existing code before suggesting changes
- Match the project's conventions (formatting, naming, patterns)
- Run tests after changes — don't assume they pass
- Prefer editing existing files over creating new ones

## Git
- Small, focused commits with descriptive messages
- Check branch and status before committing
- Never force-push to shared branches
- Stage specific files, not git add .

## Stack Detection
- Read package.json, tsconfig, Cargo.toml, etc. to detect stack
- Follow the project's toolchain (don't suggest npm if project uses pnpm)
- Use project's existing test framework, not your preference

## Regression Prevention
- Before fixing a bug, check if the same file had recent fixes
- After fixing, note what was changed and why
- Never reintroduce a pattern that was explicitly removed
```

- [ ] **Step 2: Write `configs/roles/writer.md`**

Content from spec Section 9, Writer role.

```markdown
# Role: Writer

## Communication Style
- Clear, structured prose — no technical jargon unless requested
- Use headers, bullets, and numbered lists for scannability
- Match the user's tone (formal, casual, academic, creative)
- One idea per paragraph

## Writing Process
- Ask about audience and purpose before drafting
- Provide a brief outline before writing long-form content
- Offer 2-3 alternatives for headlines, openings, or key phrases
- Track version history — label drafts as v1, v2, etc.

## Quality
- Cite sources when making factual claims
- Flag when you're uncertain about a fact
- Proofread for clarity, not just grammar
- Cut unnecessary words — every sentence earns its place
```

- [ ] **Step 3: Write `configs/roles/student.md`**

Content from spec Section 9, Student role.

```markdown
# Role: Student

## Teaching Approach
- Explain concepts before showing solutions
- Use analogies to connect new ideas to familiar ones
- Build complexity gradually — don't skip steps
- After explaining, check understanding: "Does this make sense?"

## Code Help
- Show the reasoning, not just the answer
- When fixing errors, explain what went wrong and why
- Offer simpler alternatives before advanced patterns
- Encourage the student to try first — guide, don't do

## Learning Support
- Break complex topics into digestible pieces
- Suggest what to learn next based on current level
- Provide practice exercises when relevant
- Celebrate progress without being patronizing
```

- [ ] **Step 4: Write `configs/roles/data.md`**

Content from spec Section 9, Data role.

```markdown
# Role: Data Analyst

## Analysis Standards
- State assumptions before analysis
- Cite data sources — never fabricate statistics
- Distinguish correlation from causation explicitly
- Include sample sizes and confidence levels when relevant

## Output Format
- Lead with the key finding, then supporting detail
- Use tables for comparisons, not prose
- Visualize when it clarifies — suggest chart type and axes
- Reproducibility: include the query/code that produced the result

## Data Handling
- Validate data shape and types before processing
- Flag missing values, outliers, and anomalies
- Never silently drop or modify data without noting it
- Prefer SQL/pandas operations over manual calculation
```

- [ ] **Step 5: Write `configs/roles/pm.md`**

Content from spec Section 9, PM role.

```markdown
# Role: Project Manager

## Planning
- Break work into deliverables with clear acceptance criteria
- Estimate in ranges (optimistic / likely / pessimistic), never single numbers
- Identify dependencies and blockers explicitly
- Prioritize by impact, not effort

## Communication
- Summarize for stakeholders: what, why, when, risks
- Use decision logs: options considered, decision made, rationale
- Status updates: done, in progress, blocked, next steps
- Keep technical detail proportional to audience

## Risk Management
- Flag risks early with likelihood and impact
- Propose mitigations, not just warnings
- Track assumptions that could invalidate the plan
- Escalation criteria: what triggers re-planning
```

- [ ] **Step 6: Remove .gitkeep from configs/roles/**

```bash
rm configs/roles/.gitkeep
```

- [ ] **Step 7: Verify all role files**

```bash
wc -l configs/roles/*.md
# Expected: each file ~20-30 lines
ls configs/roles/
# Expected: developer.md  writer.md  student.md  data.md  pm.md
```

- [ ] **Step 8: Commit**

```bash
git add configs/roles/
git commit -m "feat: add 5 role overlays (developer, writer, student, data, pm)"
```

---

## Task 5: Write Hook Scripts

**Files:**
- Create: `hooks/safety.sh`
- Create: `hooks/notify.sh`
- Create: `hooks/git-safety.sh`
- Create: `hooks/auto-format.sh`
- Create: `hooks/prompt-validator.sh`
- Create: `hooks/compaction-backup.sh`

- [ ] **Step 1: Write `hooks/safety.sh`**

Blocks destructive commands. Reads command from stdin (Claude Code hook protocol: tool input is passed as JSON on stdin). Exit 2 = block.

```bash
#!/usr/bin/env bash
# Claude Supercharger — Safety Hook
# Event: PreToolUse | Matcher: Bash
# Blocks destructive commands. Exit 2 = block execution.

set -euo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('input',{}).get('command',''))" 2>/dev/null || echo "")

if [ -z "$COMMAND" ]; then
  exit 0
fi

DANGEROUS_PATTERNS=(
  'rm -rf /'
  'rm -rf ~'
  'rm -rf \$HOME'
  'rm -rf \.\.'
  'DROP TABLE'
  'DROP DATABASE'
  'chmod 777'
  'chmod -R 777'
  'mkfs\.'
  'dd if='
  '> /dev/sd'
  'curl.*|.*bash'
  'curl.*|.*sh'
  'wget.*|.*bash'
  'wget.*|.*sh'
)

for pattern in "${DANGEROUS_PATTERNS[@]}"; do
  if echo "$COMMAND" | grep -qiE "$pattern"; then
    echo "BLOCKED by Supercharger safety hook: destructive command detected" >&2
    echo "Pattern matched: $pattern" >&2
    echo "Command: $COMMAND" >&2
    exit 2
  fi
done

exit 0
```

- [ ] **Step 2: Write `hooks/notify.sh`**

Platform-aware notification when Claude needs input.

```bash
#!/usr/bin/env bash
# Claude Supercharger — Notification Hook
# Event: Notification | Matcher: (none)
# Alerts user when Claude needs input.

set -euo pipefail

MESSAGE="Claude Code needs your input"

if [[ "$OSTYPE" == "darwin"* ]]; then
  osascript -e "display notification \"$MESSAGE\" with title \"Claude Supercharger\"" 2>/dev/null || true
elif command -v notify-send &>/dev/null; then
  notify-send "Claude Supercharger" "$MESSAGE" 2>/dev/null || true
else
  printf '\a'
fi

exit 0
```

- [ ] **Step 3: Write `hooks/git-safety.sh`**

Blocks dangerous git operations.

```bash
#!/usr/bin/env bash
# Claude Supercharger — Git Safety Hook
# Event: PreToolUse | Matcher: Bash
# Blocks dangerous git operations. Exit 2 = block.

set -euo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('input',{}).get('command',''))" 2>/dev/null || echo "")

if [ -z "$COMMAND" ]; then
  exit 0
fi

# Block force push to main/master
if echo "$COMMAND" | grep -qiE 'git push.*(--force|-f).*(main|master)'; then
  echo "BLOCKED by Supercharger: force push to main/master is not allowed" >&2
  exit 2
fi

# Block git push --force without branch specification (risky)
if echo "$COMMAND" | grep -qiE 'git push\s+(--force|-f)\b' && ! echo "$COMMAND" | grep -qiE 'git push.*(--force|-f).*(main|master)'; then
  echo "WARNING from Supercharger: force push detected. Verify target branch." >&2
fi

# Block git reset --hard
if echo "$COMMAND" | grep -qiE 'git reset\s+--hard'; then
  echo "BLOCKED by Supercharger: git reset --hard can destroy uncommitted work" >&2
  exit 2
fi

# Block git checkout . / git restore .
if echo "$COMMAND" | grep -qiE 'git (checkout|restore)\s+\.'; then
  echo "BLOCKED by Supercharger: this discards all unstaged changes" >&2
  exit 2
fi

# Block git clean -f (removes untracked files)
if echo "$COMMAND" | grep -qiE 'git clean\s+(-f|--force)'; then
  echo "BLOCKED by Supercharger: git clean -f permanently removes untracked files" >&2
  exit 2
fi

exit 0
```

- [ ] **Step 4: Write `hooks/auto-format.sh`**

Detects and runs project formatter after file edits.

```bash
#!/usr/bin/env bash
# Claude Supercharger — Auto-Format Hook
# Event: PostToolUse | Matcher: Write|Edit
# Runs project formatter on edited files. Developer role only.

set -euo pipefail

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('input',{}).get('file_path',''))" 2>/dev/null || echo "")

if [ -z "$FILE_PATH" ] || [ ! -f "$FILE_PATH" ]; then
  exit 0
fi

# Detect project root (look for git root or common config files)
PROJECT_ROOT=$(git -C "$(dirname "$FILE_PATH")" rev-parse --show-toplevel 2>/dev/null || dirname "$FILE_PATH")

# Try prettier (JavaScript/TypeScript ecosystem)
if [ -f "$PROJECT_ROOT/package.json" ] && grep -q '"prettier"' "$PROJECT_ROOT/package.json" 2>/dev/null; then
  if command -v npx &>/dev/null; then
    npx --yes prettier --write "$FILE_PATH" 2>/dev/null || true
    exit 0
  fi
fi

# Try black (Python)
if [ -f "$PROJECT_ROOT/pyproject.toml" ] && grep -q 'black' "$PROJECT_ROOT/pyproject.toml" 2>/dev/null; then
  if command -v black &>/dev/null; then
    black -q "$FILE_PATH" 2>/dev/null || true
    exit 0
  fi
fi

# Try rustfmt (Rust)
if [ -f "$PROJECT_ROOT/Cargo.toml" ]; then
  if command -v rustfmt &>/dev/null; then
    rustfmt "$FILE_PATH" 2>/dev/null || true
    exit 0
  fi
fi

# Try gofmt (Go)
if [ -f "$PROJECT_ROOT/go.mod" ] && [[ "$FILE_PATH" == *.go ]]; then
  if command -v gofmt &>/dev/null; then
    gofmt -w "$FILE_PATH" 2>/dev/null || true
    exit 0
  fi
fi

# No formatter detected — skip silently
exit 0
```

- [ ] **Step 5: Write `hooks/prompt-validator.sh`**

Scans user prompt for anti-patterns. Enhances, never blocks.

```bash
#!/usr/bin/env bash
# Claude Supercharger — Prompt Validator Hook
# Event: UserPromptSubmit | Matcher: (none)
# Scans prompt for anti-patterns. Adds notes, never blocks.

set -euo pipefail

INPUT=$(cat)
PROMPT=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('input',{}).get('prompt',''))" 2>/dev/null || echo "")

if [ -z "$PROMPT" ]; then
  exit 0
fi

NOTES=""

# Check for vague scope
if echo "$PROMPT" | grep -qiE '^(fix|update|change|improve|make)\s+(it|this|that|the app|the code)\b'; then
  NOTES="${NOTES}[Supercharger] Consider specifying which files or functions to target.\n"
fi

# Check for multiple tasks
if echo "$PROMPT" | grep -qiE '\b(and also|and then|plus|additionally)\b.*\b(and also|and then|plus|additionally)\b'; then
  NOTES="${NOTES}[Supercharger] Multiple tasks detected. Consider splitting into separate requests.\n"
fi

# Check for vague success criteria
if echo "$PROMPT" | grep -qiE '\b(make it better|improve|optimize|clean up)\b' && ! echo "$PROMPT" | grep -qiE '\b(should|must|ensure|so that|such that)\b'; then
  NOTES="${NOTES}[Supercharger] Consider adding success criteria (what does 'better' mean here?).\n"
fi

if [ -n "$NOTES" ]; then
  echo -e "$NOTES" >&2
fi

exit 0
```

- [ ] **Step 6: Write `hooks/compaction-backup.sh`**

Saves conversation transcript before compaction.

```bash
#!/usr/bin/env bash
# Claude Supercharger — Compaction Backup Hook
# Event: PreCompact | Matcher: (none)
# Saves conversation transcript before context compaction.

set -euo pipefail

BACKUP_DIR="$HOME/.claude/backups/transcripts"
mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"

TIMESTAMP=$(date +%Y-%m-%d-%H%M%S)
BACKUP_FILE="$BACKUP_DIR/$TIMESTAMP.md"

INPUT=$(cat)
echo "$INPUT" > "$BACKUP_FILE"
chmod 600 "$BACKUP_FILE"

echo "Transcript backed up to $BACKUP_FILE" >&2

exit 0
```

- [ ] **Step 7: Make all hooks executable**

```bash
chmod +x hooks/*.sh
```

- [ ] **Step 8: Remove .gitkeep from hooks/**

```bash
rm hooks/.gitkeep
```

- [ ] **Step 9: Syntax check all hooks**

```bash
for f in hooks/*.sh; do bash -n "$f" && echo "OK: $f"; done
# Expected: OK for all 6 files
```

- [ ] **Step 10: Commit**

```bash
git add hooks/
git commit -m "feat: add 6 hook scripts (safety, notify, git-safety, auto-format, prompt-validator, compaction-backup)"
```

---

## Task 6: Write `lib/utils.sh`

**Files:**
- Create: `lib/utils.sh`

- [ ] **Step 1: Write `lib/utils.sh`**

```bash
#!/usr/bin/env bash
# Claude Supercharger — Utility Functions

VERSION="1.0.0"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Logging
info()    { echo -e "${BLUE}$1${NC}"; }
success() { echo -e "${GREEN}  ✓ $1${NC}"; }
warn()    { echo -e "${YELLOW}  ⚠ $1${NC}"; }
error()   { echo -e "${RED}  ✗ $1${NC}"; }

# Platform detection
detect_platform() {
  case "$OSTYPE" in
    darwin*)  PLATFORM="macos" ;;
    linux*)   PLATFORM="linux" ;;
    *)        PLATFORM="unknown" ;;
  esac
}

# Banner
show_banner() {
  echo -e "${CYAN}"
  echo "╔═══════════════════════════════════════════╗"
  echo "║    Claude Supercharger v${VERSION} Installer   ║"
  echo "╚═══════════════════════════════════════════╝"
  echo -e "${NC}"
}

# Resolve script directory (works even when sourced)
resolve_script_dir() {
  local source="${BASH_SOURCE[1]:-$0}"
  local dir
  dir=$(cd "$(dirname "$source")" && pwd)
  # If we're in lib/, go up one level
  if [[ "$(basename "$dir")" == "lib" ]]; then
    dir=$(dirname "$dir")
  fi
  echo "$dir"
}
```

- [ ] **Step 2: Syntax check**

```bash
bash -n lib/utils.sh && echo "OK"
```

- [ ] **Step 3: Commit**

```bash
git add lib/utils.sh
git commit -m "feat: add lib/utils.sh (colors, logging, platform detection)"
```

---

## Task 7: Write `lib/backup.sh`

**Files:**
- Create: `lib/backup.sh`

- [ ] **Step 1: Write `lib/backup.sh`**

```bash
#!/usr/bin/env bash
# Claude Supercharger — Backup/Restore Functions

create_backup() {
  local timestamp
  timestamp=$(date +%Y%m%d-%H%M%S)
  BACKUP_DIR="$HOME/.claude/backups/$timestamp"
  mkdir -p "$BACKUP_DIR"
  chmod 700 "$BACKUP_DIR"

  # Copy existing configs (only .md files and shared/)
  if [ -d "$HOME/.claude" ]; then
    cp "$HOME/.claude/"*.md "$BACKUP_DIR/" 2>/dev/null || true
    if [ -d "$HOME/.claude/rules" ]; then
      cp -r "$HOME/.claude/rules" "$BACKUP_DIR/" 2>/dev/null || true
    fi
    if [ -d "$HOME/.claude/shared" ]; then
      cp -r "$HOME/.claude/shared" "$BACKUP_DIR/" 2>/dev/null || true
    fi
    if [ -f "$HOME/.claude/settings.json" ]; then
      cp "$HOME/.claude/settings.json" "$BACKUP_DIR/" 2>/dev/null || true
    fi
  fi

  success "Backed up ~/.claude/ to $BACKUP_DIR/"
}

find_latest_backup() {
  local latest=""
  if [ -d "$HOME/.claude/backups" ]; then
    for d in "$HOME/.claude/backups"/*/; do
      [ -d "$d" ] && latest="$d"
    done
  fi
  echo "$latest"
}

restore_backup() {
  local backup_dir="$1"
  if [ -z "$backup_dir" ] || [ ! -d "$backup_dir" ]; then
    warn "No backup found to restore"
    return 1
  fi

  # Restore files
  cp "$backup_dir"*.md "$HOME/.claude/" 2>/dev/null || true
  if [ -d "${backup_dir}rules" ]; then
    cp -r "${backup_dir}rules" "$HOME/.claude/" 2>/dev/null || true
  fi
  if [ -d "${backup_dir}shared" ]; then
    cp -r "${backup_dir}shared" "$HOME/.claude/" 2>/dev/null || true
  fi
  if [ -f "${backup_dir}settings.json" ]; then
    cp "${backup_dir}settings.json" "$HOME/.claude/" 2>/dev/null || true
  fi

  success "Restored from backup"
}
```

- [ ] **Step 2: Syntax check**

```bash
bash -n lib/backup.sh && echo "OK"
```

- [ ] **Step 3: Commit**

```bash
git add lib/backup.sh
git commit -m "feat: add lib/backup.sh (backup/restore functions)"
```

---

## Task 8: Write `lib/roles.sh`

**Files:**
- Create: `lib/roles.sh`

- [ ] **Step 1: Write `lib/roles.sh`**

```bash
#!/usr/bin/env bash
# Claude Supercharger — Role Selection & Deployment

AVAILABLE_ROLES=("developer" "writer" "student" "data" "pm")
ROLE_LABELS=("Developer — build things" "Writer — communicate things" "Student — learn things" "Data — analyze things" "PM — plan things")
SELECTED_ROLES=()

select_roles() {
  echo ""
  info "Which roles describe you? (comma-separated, or 'all')"
  echo ""
  for i in "${!AVAILABLE_ROLES[@]}"; do
    echo -e "  ${BOLD}$((i+1)))${NC} ${ROLE_LABELS[$i]}"
  done
  echo ""

  local input
  read -rp "> " input

  if [[ "$input" == "all" ]]; then
    SELECTED_ROLES=("${AVAILABLE_ROLES[@]}")
    return
  fi

  # Parse comma-separated numbers
  IFS=',' read -ra selections <<< "$input"
  for sel in "${selections[@]}"; do
    sel=$(echo "$sel" | tr -d ' ')
    if [[ "$sel" =~ ^[0-9]+$ ]] && [ "$sel" -ge 1 ] && [ "$sel" -le "${#AVAILABLE_ROLES[@]}" ]; then
      SELECTED_ROLES+=("${AVAILABLE_ROLES[$((sel-1))]}")
    else
      warn "Invalid selection: $sel (skipping)"
    fi
  done

  if [ ${#SELECTED_ROLES[@]} -eq 0 ]; then
    warn "No valid roles selected. Defaulting to Writer."
    SELECTED_ROLES=("writer")
  fi
}

deploy_roles() {
  local source_dir="$1"
  local target_dir="$HOME/.claude/rules"
  mkdir -p "$target_dir"

  for role in "${SELECTED_ROLES[@]}"; do
    local role_file="$source_dir/configs/roles/${role}.md"
    if [ -f "$role_file" ]; then
      cp "$role_file" "$target_dir/${role}.md"
      success "Role installed: ${role}"
    else
      warn "Role file not found: ${role}.md"
    fi
  done
}

format_roles_list() {
  local result=""
  for role in "${SELECTED_ROLES[@]}"; do
    # Capitalize first letter
    local capitalized
    capitalized="$(echo "${role:0:1}" | tr '[:lower:]' '[:upper:]')${role:1}"
    if [ -n "$result" ]; then
      result="$result, $capitalized"
    else
      result="$capitalized"
    fi
  done
  echo "$result"
}
```

- [ ] **Step 2: Syntax check**

```bash
bash -n lib/roles.sh && echo "OK"
```

- [ ] **Step 3: Commit**

```bash
git add lib/roles.sh
git commit -m "feat: add lib/roles.sh (multi-select role UI + deployment)"
```

---

## Task 9: Write `lib/hooks.sh`

**Files:**
- Create: `lib/hooks.sh`

This is the most complex module. It assembles hooks based on mode + role and merges them into settings.json.

- [ ] **Step 1: Write `lib/hooks.sh`**

```bash
#!/usr/bin/env bash
# Claude Supercharger — Hook Assembly & settings.json Merge

SUPERCHARGER_TAG="#supercharger"

get_hooks_for_mode() {
  local mode="$1"
  local has_developer="$2"
  local hooks_dir="$3"
  local hooks=()

  # Safe mode: safety only
  hooks+=("PreToolUse|Bash|${hooks_dir}/safety.sh")

  if [[ "$mode" == "standard" || "$mode" == "full" ]]; then
    hooks+=("Notification||${hooks_dir}/notify.sh")
    hooks+=("PreToolUse|Bash|${hooks_dir}/git-safety.sh")
    if [[ "$has_developer" == "true" ]]; then
      hooks+=("PostToolUse|Write,Edit|${hooks_dir}/auto-format.sh")
    fi
  fi

  if [[ "$mode" == "full" ]]; then
    hooks+=("UserPromptSubmit||${hooks_dir}/prompt-validator.sh")
    hooks+=("PreCompact||${hooks_dir}/compaction-backup.sh")
  fi

  printf '%s\n' "${hooks[@]}"
}

deploy_hook_scripts() {
  local source_dir="$1"
  local target_dir="$HOME/.claude/supercharger/hooks"
  mkdir -p "$target_dir"
  chmod 700 "$HOME/.claude/supercharger"

  cp "$source_dir/hooks/"*.sh "$target_dir/"
  chmod +x "$target_dir/"*.sh
}

merge_hooks_into_settings() {
  local mode="$1"
  local has_developer="$2"
  local hooks_dir="$HOME/.claude/supercharger/hooks"
  local settings_file="$HOME/.claude/settings.json"

  # Get hooks for this mode
  local hooks_list
  hooks_list=$(get_hooks_for_mode "$mode" "$has_developer" "$hooks_dir")

  # Build and merge using Python (safe JSON handling)
  python3 -c "
import json, os, sys

settings_file = os.path.expanduser('$settings_file')
tag = '$SUPERCHARGER_TAG'

# Load existing or create new
if os.path.exists(settings_file):
    with open(settings_file, 'r') as f:
        try:
            settings = json.load(f)
        except json.JSONDecodeError:
            print('ERROR: settings.json is malformed. Use Replace or Skip.', file=sys.stderr)
            sys.exit(1)
else:
    settings = {}

if 'hooks' not in settings:
    settings['hooks'] = {}

# Remove existing supercharger hooks first (idempotent)
for event in list(settings['hooks'].keys()):
    settings['hooks'][event] = [
        h for h in settings['hooks'][event]
        if tag not in h.get('command', '')
    ]
    # Remove empty event arrays
    if not settings['hooks'][event]:
        del settings['hooks'][event]

# Add new hooks
hooks_input = '''$hooks_list'''
for line in hooks_input.strip().split('\n'):
    if not line.strip():
        continue
    parts = line.split('|', 2)
    event = parts[0]
    matcher = parts[1] if len(parts) > 1 else ''
    command = parts[2] if len(parts) > 2 else ''

    if event not in settings['hooks']:
        settings['hooks'][event] = []

    hook_entry = {'command': command + ' ' + tag}
    if matcher:
        hook_entry['matcher'] = matcher

    settings['hooks'][event].append(hook_entry)

with open(settings_file, 'w') as f:
    json.dump(settings, f, indent=2)
" 2>&1

  return $?
}

remove_supercharger_hooks() {
  local settings_file="$HOME/.claude/settings.json"

  if [ ! -f "$settings_file" ]; then
    return 0
  fi

  python3 -c "
import json, os

settings_file = os.path.expanduser('$settings_file')
tag = '$SUPERCHARGER_TAG'

with open(settings_file, 'r') as f:
    settings = json.load(f)

if 'hooks' in settings:
    for event in list(settings['hooks'].keys()):
        settings['hooks'][event] = [
            h for h in settings['hooks'][event]
            if tag not in h.get('command', '')
        ]
        if not settings['hooks'][event]:
            del settings['hooks'][event]
    if not settings['hooks']:
        del settings['hooks']

with open(settings_file, 'w') as f:
    json.dump(settings, f, indent=2)
" 2>&1
}

count_installed_hooks() {
  local mode="$1"
  local has_developer="$2"
  local count=1  # safety always

  if [[ "$mode" == "standard" || "$mode" == "full" ]]; then
    count=$((count + 2))  # notify + git-safety
    if [[ "$has_developer" == "true" ]]; then
      count=$((count + 1))  # auto-format
    fi
  fi

  if [[ "$mode" == "full" ]]; then
    count=$((count + 2))  # prompt-validator + compaction-backup
  fi

  echo "$count"
}
```

- [ ] **Step 2: Syntax check**

```bash
bash -n lib/hooks.sh && echo "OK"
```

- [ ] **Step 3: Commit**

```bash
git add lib/hooks.sh
git commit -m "feat: add lib/hooks.sh (hook assembly + settings.json merge)"
```

---

## Task 10: Write `lib/extras.sh`

**Files:**
- Create: `lib/extras.sh`

- [ ] **Step 1: Write `lib/extras.sh`**

```bash
#!/usr/bin/env bash
# Claude Supercharger — Extras Deployment (Full mode)

deploy_extras() {
  local source_dir="$1"
  local mode="$2"

  if [[ "$mode" != "full" ]]; then
    return 0
  fi

  # Deploy guardrails template
  if [ -f "$source_dir/shared/guardrails-template.yml" ]; then
    cp "$source_dir/shared/guardrails-template.yml" "$HOME/.claude/shared/"
    success "Guardrails template installed"
  fi

  # Deploy claude-check
  if [ -f "$source_dir/tools/claude-check.sh" ]; then
    cp "$source_dir/tools/claude-check.sh" "$HOME/.claude/claude-check.sh"
    chmod +x "$HOME/.claude/claude-check.sh"
    success "claude-check diagnostic installed"
  fi

  # Offer MCP setup
  echo ""
  info "MCP Server Setup"
  echo -e "  Configure MCP servers for enhanced Claude Code capabilities?"
  read -rp "  Run MCP setup? (y/N): " mcp_choice
  echo
  if [[ "$mcp_choice" =~ ^[Yy]$ ]]; then
    if [ -f "$source_dir/tools/mcp-setup.sh" ]; then
      bash "$source_dir/tools/mcp-setup.sh"
    else
      warn "MCP setup script not found"
    fi
  else
    info "Skipped MCP setup. Run tools/mcp-setup.sh later if needed."
  fi
}
```

- [ ] **Step 2: Syntax check**

```bash
bash -n lib/extras.sh && echo "OK"
```

- [ ] **Step 3: Remove .gitkeep from lib/**

```bash
rm lib/.gitkeep
```

- [ ] **Step 4: Commit**

```bash
git add lib/extras.sh
git commit -m "feat: add lib/extras.sh (MCP setup, guardrails template, diagnostic)"
```

---

## Task 11: Write `tools/claude-check.sh`

**Files:**
- Create: `tools/claude-check.sh`

- [ ] **Step 1: Write `tools/claude-check.sh`**

```bash
#!/usr/bin/env bash
# Claude Supercharger — Installation Health Check
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}"
echo "╔═══════════════════════════════════════════╗"
echo "║    Claude Supercharger Health Check       ║"
echo "╚═══════════════════════════════════════════╝"
echo -e "${NC}"

ERRORS=0

check_file() {
  local path="$1"
  local label="$2"
  if [ -f "$path" ]; then
    echo -e "  ${GREEN}✓${NC} $label"
  else
    echo -e "  ${RED}✗${NC} $label — ${RED}missing${NC}"
    ERRORS=$((ERRORS + 1))
  fi
}

check_dir() {
  local path="$1"
  local label="$2"
  if [ -d "$path" ]; then
    echo -e "  ${GREEN}✓${NC} $label"
  else
    echo -e "  ${YELLOW}○${NC} $label — not installed"
  fi
}

# Config Files
echo -e "${BLUE}Config Files:${NC}"
check_file "$HOME/.claude/CLAUDE.md" "CLAUDE.md"
check_file "$HOME/.claude/rules/supercharger.md" "rules/supercharger.md — universal rules"
check_file "$HOME/.claude/rules/guardrails.md" "rules/guardrails.md — Four Laws + safety"

# Detect installed roles
echo ""
echo -e "${BLUE}Roles:${NC}"
ROLES_FOUND=""
for role in developer writer student data pm; do
  if [ -f "$HOME/.claude/rules/${role}.md" ]; then
    ROLE_LABEL=$(echo "${role:0:1}" | tr '[:lower:]' '[:upper:]')${role:1}
    echo -e "  ${GREEN}✓${NC} ${ROLE_LABEL}"
    ROLES_FOUND="${ROLES_FOUND:+$ROLES_FOUND, }$ROLE_LABEL"
  fi
done
if [ -z "$ROLES_FOUND" ]; then
  echo -e "  ${YELLOW}○${NC} No role overlays found"
fi

# Shared assets
echo ""
echo -e "${BLUE}Shared Assets:${NC}"
check_file "$HOME/.claude/shared/anti-patterns.yml" "anti-patterns.yml"
if [ -f "$HOME/.claude/shared/guardrails-template.yml" ]; then
  echo -e "  ${GREEN}✓${NC} guardrails-template.yml (Full mode)"
else
  echo -e "  ${YELLOW}○${NC} guardrails-template.yml — not installed (Full mode)"
fi

# Hooks
echo ""
echo -e "${BLUE}Hooks:${NC}"
if [ -f "$HOME/.claude/settings.json" ]; then
  HOOK_COUNT=$(python3 -c "
import json
with open('$HOME/.claude/settings.json') as f:
    s = json.load(f)
hooks = s.get('hooks', {})
count = sum(1 for event in hooks.values() for h in event if '#supercharger' in h.get('command',''))
print(count)
" 2>/dev/null || echo "0")
  echo -e "  ${GREEN}✓${NC} settings.json valid — ${HOOK_COUNT} Supercharger hook(s) registered"

  # Check individual hooks
  check_dir "$HOME/.claude/supercharger/hooks" "Hook scripts directory"
  if [ -d "$HOME/.claude/supercharger/hooks" ]; then
    for hook in safety notify git-safety auto-format prompt-validator compaction-backup; do
      if [ -f "$HOME/.claude/supercharger/hooks/${hook}.sh" ]; then
        # Check if registered in settings.json
        if grep -q "${hook}.sh" "$HOME/.claude/settings.json" 2>/dev/null; then
          echo -e "    ${GREEN}✓${NC} ${hook} — active"
        else
          echo -e "    ${YELLOW}○${NC} ${hook} — installed but not active"
        fi
      fi
    done
  fi
else
  echo -e "  ${YELLOW}○${NC} No settings.json — no hooks installed"
fi

# Tools
echo ""
echo -e "${BLUE}Tools:${NC}"
if [ -f "$HOME/.claude/claude-check.sh" ]; then
  echo -e "  ${GREEN}✓${NC} claude-check — installed"
else
  echo -e "  ${YELLOW}○${NC} claude-check — not installed (Full mode)"
fi

# Summary
echo ""
echo -e "${CYAN}────────────────────────────────────────────${NC}"
if [ -n "$ROLES_FOUND" ]; then
  echo -e "Roles: ${BOLD}$ROLES_FOUND${NC}"
fi
echo -e "Version: ${BOLD}1.0.0${NC}"
echo ""

if [ "$ERRORS" -eq 0 ]; then
  echo -e "${GREEN}All checks passed ✓${NC}"
else
  echo -e "${RED}${ERRORS} issue(s) found. Run install.sh to fix.${NC}"
fi
```

- [ ] **Step 2: Make executable and syntax check**

```bash
chmod +x tools/claude-check.sh
bash -n tools/claude-check.sh && echo "OK"
```

- [ ] **Step 3: Commit**

```bash
git add tools/claude-check.sh
git commit -m "feat: add claude-check diagnostic tool"
```

---

## Task 12: Write `install.sh`

**Files:**
- Rewrite: `install.sh`

- [ ] **Step 1: Write `install.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
umask 077

# Resolve source directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source modules
source "$SCRIPT_DIR/lib/utils.sh"
source "$SCRIPT_DIR/lib/backup.sh"
source "$SCRIPT_DIR/lib/roles.sh"
source "$SCRIPT_DIR/lib/hooks.sh"
source "$SCRIPT_DIR/lib/extras.sh"

detect_platform

# Step 1: Banner + Mode
show_banner
echo -e "${BOLD}Step 1 of 4: Install Mode${NC}"
echo ""
echo -e "  ${BOLD}1)${NC} Safe       — configs + safety hooks only"
echo -e "  ${BOLD}2)${NC} Standard   — recommended (configs + hooks + productivity)"
echo -e "  ${BOLD}3)${NC} Full       — everything (+ MCP setup + diagnostics)"
echo ""
read -rp "> " mode_choice
case "$mode_choice" in
  1) MODE="safe" ;;
  3) MODE="full" ;;
  *) MODE="standard" ;;
esac
echo ""

# Step 2: Roles
echo -e "${BOLD}Step 2 of 4: Your Roles${NC}"
select_roles
echo ""

# Check if Developer role is selected
HAS_DEVELOPER="false"
for role in "${SELECTED_ROLES[@]}"; do
  [[ "$role" == "developer" ]] && HAS_DEVELOPER="true"
done

# Step 3: Existing config handling
echo -e "${BOLD}Step 3 of 4: Existing Config${NC}"
echo ""

CLAUDE_MD_ACTION="deploy"
if [ -f "$HOME/.claude/CLAUDE.md" ]; then
  info "Found existing CLAUDE.md"
  echo ""
  echo -e "  ${BOLD}1)${NC} Merge   — append Supercharger to your existing file"
  echo -e "  ${BOLD}2)${NC} Replace — back up yours, use Supercharger's"
  echo -e "  ${BOLD}3)${NC} Skip    — keep yours, install everything else"
  echo ""
  read -rp "> " claude_choice
  case "$claude_choice" in
    1) CLAUDE_MD_ACTION="merge" ;;
    3) CLAUDE_MD_ACTION="skip" ;;
    *) CLAUDE_MD_ACTION="replace" ;;
  esac
  echo ""
fi

SETTINGS_ACTION="deploy"
if [ -f "$HOME/.claude/settings.json" ]; then
  info "Found existing settings.json"
  echo ""
  echo -e "  ${BOLD}1)${NC} Merge   — add Supercharger hooks to your config"
  echo -e "  ${BOLD}2)${NC} Replace — back up yours, use Supercharger's"
  echo -e "  ${BOLD}3)${NC} Skip    — keep yours, no hooks installed"
  echo ""
  read -rp "> " settings_choice
  case "$settings_choice" in
    1) SETTINGS_ACTION="merge" ;;
    3) SETTINGS_ACTION="skip" ;;
    *) SETTINGS_ACTION="replace" ;;
  esac
  echo ""
fi

# Step 4: Install
echo -e "${BOLD}Step 4 of 4: Installing...${NC}"
echo ""

# Ensure directories exist
mkdir -p "$HOME/.claude/rules"
mkdir -p "$HOME/.claude/shared"

# Backup
create_backup

# Deploy CLAUDE.md
ROLES_LIST=$(format_roles_list)
MODE_LABEL=$(echo "$MODE" | sed 's/^./\U&/')

if [[ "$CLAUDE_MD_ACTION" == "deploy" || "$CLAUDE_MD_ACTION" == "replace" ]]; then
  sed -e "s/{{ROLES}}/$ROLES_LIST/g" -e "s/{{MODE}}/$MODE_LABEL/g" \
    "$SCRIPT_DIR/configs/universal/CLAUDE.md" > "$HOME/.claude/CLAUDE.md"
  success "Universal config installed"
elif [[ "$CLAUDE_MD_ACTION" == "merge" ]]; then
  # Remove existing Supercharger block if present
  if grep -q "^# --- Claude Supercharger" "$HOME/.claude/CLAUDE.md" 2>/dev/null; then
    sed -i.bak '/^# --- Claude Supercharger/,$d' "$HOME/.claude/CLAUDE.md"
    rm -f "$HOME/.claude/CLAUDE.md.bak"
  fi
  # Append Supercharger block
  cat >> "$HOME/.claude/CLAUDE.md" << MERGEBLOCK

# --- Claude Supercharger v${VERSION} ---
# Do not edit below this line. Managed by Supercharger.
# To remove: run uninstall.sh or delete this block.
# Roles: ${ROLES_LIST} | Mode: ${MODE_LABEL}
MERGEBLOCK
  success "Universal config merged (your CLAUDE.md preserved)"
elif [[ "$CLAUDE_MD_ACTION" == "skip" ]]; then
  info "Skipped CLAUDE.md"
fi

# Deploy universal rules
cp "$SCRIPT_DIR/configs/universal/supercharger.md" "$HOME/.claude/rules/supercharger.md"
success "Universal rules installed"

cp "$SCRIPT_DIR/configs/universal/guardrails.md" "$HOME/.claude/rules/guardrails.md"
success "Guardrails installed"

# Deploy roles
deploy_roles "$SCRIPT_DIR"

# Deploy shared assets
cp "$SCRIPT_DIR/shared/anti-patterns.yml" "$HOME/.claude/shared/anti-patterns.yml"
success "Anti-patterns library installed"

# Deploy hooks
if [[ "$SETTINGS_ACTION" != "skip" ]]; then
  deploy_hook_scripts "$SCRIPT_DIR"

  if [[ "$SETTINGS_ACTION" == "replace" ]] && [ -f "$HOME/.claude/settings.json" ]; then
    rm "$HOME/.claude/settings.json"
  fi

  if merge_hooks_into_settings "$MODE" "$HAS_DEVELOPER"; then
    HOOK_COUNT=$(count_installed_hooks "$MODE" "$HAS_DEVELOPER")
    success "${HOOK_COUNT} hook(s) installed (${MODE_LABEL} mode)"
  else
    error "Failed to configure hooks. Run claude-check for details."
  fi
else
  info "Skipped hooks installation"
fi

# Deploy extras (Full mode)
deploy_extras "$SCRIPT_DIR" "$MODE"

# Summary
echo ""
echo -e "${CYAN}────────────────────────────────────────────${NC}"
echo -e "${GREEN}  Done! Claude Supercharger v${VERSION} installed.${NC}"
echo ""
echo -e "  Mode:  ${BOLD}${MODE_LABEL}${NC}"
echo -e "  Roles: ${BOLD}${ROLES_LIST}${NC}"
echo ""
if [[ "$MODE" == "full" ]]; then
  echo -e "  Run ${BOLD}claude-check${NC} to verify installation."
else
  echo -e "  Upgrade anytime: ${BOLD}./install.sh${NC} (choose Full)"
fi
echo ""
```

- [ ] **Step 2: Make executable and syntax check**

```bash
chmod +x install.sh
bash -n install.sh && echo "OK"
```

- [ ] **Step 3: Commit**

```bash
git add install.sh
git commit -m "feat: rewrite install.sh as modular role-aware orchestrator"
```

---

## Task 13: Write `uninstall.sh`

**Files:**
- Rewrite: `uninstall.sh`

- [ ] **Step 1: Write `uninstall.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
umask 077

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${CYAN}"
echo "╔═══════════════════════════════════════════╗"
echo "║   Claude Supercharger v1.0 Uninstaller    ║"
echo "╚═══════════════════════════════════════════╝"
echo -e "${NC}"

read -rp "Are you sure you want to uninstall Claude Supercharger? (y/N): " -n 1
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo -e "${BLUE}Uninstall cancelled.${NC}"
  exit 0
fi

# Find most recent backup
BACKUP_DIR=""
if [ -d "$HOME/.claude/backups" ]; then
  for d in "$HOME/.claude/backups"/*/; do
    [ -d "$d" ] && BACKUP_DIR="$d"
  done
fi

RESTORE="false"
if [ -n "$BACKUP_DIR" ]; then
  echo -e "${BLUE}Found backup: $BACKUP_DIR${NC}"
  read -rp "Restore from this backup? (Y/n): " -n 1
  echo
  if [[ ! $REPLY =~ ^[Nn]$ ]]; then
    RESTORE="true"
  fi
fi

echo ""
echo -e "${BLUE}Removing Supercharger...${NC}"

# Remove hooks from settings.json
if [ -f "$HOME/.claude/settings.json" ]; then
  python3 -c "
import json, os

settings_file = os.path.expanduser('$HOME/.claude/settings.json')
tag = '#supercharger'

with open(settings_file, 'r') as f:
    settings = json.load(f)

if 'hooks' in settings:
    for event in list(settings['hooks'].keys()):
        settings['hooks'][event] = [
            h for h in settings['hooks'][event]
            if tag not in h.get('command', '')
        ]
        if not settings['hooks'][event]:
            del settings['hooks'][event]
    if not settings['hooks']:
        del settings['hooks']

with open(settings_file, 'w') as f:
    json.dump(settings, f, indent=2)
" 2>/dev/null && echo -e "  ${GREEN}✓${NC} Hooks removed from settings.json"
fi

# Remove Supercharger block from CLAUDE.md
if [ -f "$HOME/.claude/CLAUDE.md" ] && grep -q "^# --- Claude Supercharger" "$HOME/.claude/CLAUDE.md" 2>/dev/null; then
  sed -i.bak '/^# --- Claude Supercharger/,$d' "$HOME/.claude/CLAUDE.md"
  rm -f "$HOME/.claude/CLAUDE.md.bak"
  # Remove trailing blank lines
  sed -i.bak -e :a -e '/^\n*$/{$d;N;ba' -e '}' "$HOME/.claude/CLAUDE.md"
  rm -f "$HOME/.claude/CLAUDE.md.bak"
  echo -e "  ${GREEN}✓${NC} Supercharger block removed from CLAUDE.md"
fi

# Remove Supercharger rule files
for f in supercharger.md guardrails.md developer.md writer.md student.md data.md pm.md; do
  rm -f "$HOME/.claude/rules/$f"
done
echo -e "  ${GREEN}✓${NC} Rule files removed"

# Remove shared assets
rm -f "$HOME/.claude/shared/anti-patterns.yml"
rm -f "$HOME/.claude/shared/guardrails-template.yml"
echo -e "  ${GREEN}✓${NC} Shared assets removed"

# Remove hook scripts
rm -rf "$HOME/.claude/supercharger"
echo -e "  ${GREEN}✓${NC} Hook scripts removed"

# Remove claude-check
rm -f "$HOME/.claude/claude-check.sh"

# Restore backup if requested
if [[ "$RESTORE" == "true" ]]; then
  echo ""
  cp "${BACKUP_DIR}"*.md "$HOME/.claude/" 2>/dev/null || true
  if [ -d "${BACKUP_DIR}rules" ]; then
    cp -r "${BACKUP_DIR}rules" "$HOME/.claude/" 2>/dev/null || true
  fi
  if [ -d "${BACKUP_DIR}shared" ]; then
    cp -r "${BACKUP_DIR}shared" "$HOME/.claude/" 2>/dev/null || true
  fi
  if [ -f "${BACKUP_DIR}settings.json" ]; then
    cp "${BACKUP_DIR}settings.json" "$HOME/.claude/" 2>/dev/null || true
  fi
  echo -e "  ${GREEN}✓${NC} Backup restored"
fi

echo ""
echo -e "${GREEN}Uninstall complete.${NC}"
echo -e "${YELLOW}Note: Backup preserved at ${BACKUP_DIR:-'(no backup)'}${NC}"
echo ""
```

- [ ] **Step 2: Make executable and syntax check**

```bash
chmod +x uninstall.sh
bash -n uninstall.sh && echo "OK"
```

- [ ] **Step 3: Commit**

```bash
git add uninstall.sh
git commit -m "feat: rewrite uninstall.sh for clean Supercharger removal"
```

---

## Task 14: Update README.md

**Files:**
- Rewrite: `README.md`

- [ ] **Step 1: Write new README.md**

Complete rewrite for the new project. Should include:

- One-line description
- What it does (brief)
- Install command (`curl | bash`)
- The 3 install modes explained
- The 5 roles explained
- What hooks are included
- Uninstall command
- How to verify (`claude-check`)
- Credits (SuperClaude, TheArchitectit)
- License (MIT + BSD-3)

Keep it under 200 lines. Lead with the install command — most users just want to get started.

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: rewrite README for v1.0"
```

---

## Task 15: Update LICENSE and CHANGELOG

**Files:**
- Modify: `LICENSE`
- Rewrite: `CHANGELOG.md`

- [ ] **Step 1: Update LICENSE**

Keep MIT for the project. Include BSD-3-Clause attribution for TheArchitectit guardrails content (already present from our earlier fix). Update copyright to 2026, smrafiz.

- [ ] **Step 2: Write CHANGELOG.md**

```markdown
# Changelog

## [1.0.0] - 2026-03-31

### New
- Role-based installer with 5 roles: Developer, Writer, Student, Data, PM
- 3 install modes: Safe, Standard, Full
- Multi-select role support (combine any roles)
- Universal CLAUDE.md (~50 lines) with verification gate and safety boundaries
- Universal rules (supercharger.md) with execution workflow and anti-pattern detection
- Guardrails system inspired by TheArchitectit/agent-guardrails-template (Four Laws, autonomy levels, halt conditions)
- 6 hooks: safety, notify, git-safety, auto-format, prompt-validator, compaction-backup
- Existing config handling: Merge / Replace / Skip for CLAUDE.md and settings.json
- MCP server setup tool (12 servers supported)
- claude-check diagnostic tool
- Clean uninstaller with backup restore
- Anti-patterns library (35 patterns)

### Credits
- Inspired by SuperClaude Framework (MIT) — execution workflow patterns
- Guardrails adapted from TheArchitectit/agent-guardrails-template (BSD-3)
```

- [ ] **Step 3: Commit**

```bash
git add LICENSE CHANGELOG.md
git commit -m "docs: update LICENSE and CHANGELOG for v1.0"
```

---

## Task 16: Update .gitignore

**Files:**
- Modify: `.gitignore`

- [ ] **Step 1: Update .gitignore**

```
.DS_Store
*.swp
*.swo
*~
.claude/
```

- [ ] **Step 2: Commit**

```bash
git add .gitignore
git commit -m "chore: update .gitignore for v1.0"
```

---

## Task 17: Integration Test

Verify the full install/uninstall cycle works end-to-end.

- [ ] **Step 1: Syntax check all shell files**

```bash
for f in install.sh uninstall.sh lib/*.sh hooks/*.sh tools/*.sh; do
  bash -n "$f" && echo "OK: $f" || echo "FAIL: $f"
done
# Expected: OK for all files
```

- [ ] **Step 2: Test fresh install (Standard mode, Developer + PM)**

```bash
# Backup current ~/.claude/ manually first
cp -r ~/.claude/ /tmp/claude-backup-test/

# Run installer
./install.sh
# Choose: 2 (Standard), 1,5 (Developer+PM), and appropriate config choices
```

- [ ] **Step 3: Verify with claude-check**

```bash
bash tools/claude-check.sh
# Expected: all checks pass, Developer + PM roles shown, 4 hooks active
```

- [ ] **Step 4: Verify hook registration**

```bash
python3 -c "
import json
with open('$HOME/.claude/settings.json') as f:
    s = json.load(f)
for event, hooks in s.get('hooks', {}).items():
    for h in hooks:
        if '#supercharger' in h.get('command', ''):
            print(f'{event}: {h}')
"
# Expected: 4 hooks (safety, notify, git-safety, auto-format)
```

- [ ] **Step 5: Verify config files**

```bash
ls -la ~/.claude/rules/
# Expected: supercharger.md, guardrails.md, developer.md, pm.md

ls -la ~/.claude/shared/
# Expected: anti-patterns.yml

cat ~/.claude/CLAUDE.md | head -5
# Expected: either merged block or fresh Supercharger config
```

- [ ] **Step 6: Test uninstall**

```bash
./uninstall.sh
# Choose: y to confirm, Y to restore backup
```

- [ ] **Step 7: Verify clean uninstall**

```bash
ls ~/.claude/rules/supercharger.md 2>/dev/null && echo "FAIL: rules not removed" || echo "OK: rules removed"
ls ~/.claude/supercharger/ 2>/dev/null && echo "FAIL: hooks dir not removed" || echo "OK: hooks dir removed"
grep -q "supercharger" ~/.claude/settings.json 2>/dev/null && echo "FAIL: hooks in settings" || echo "OK: hooks removed"
grep -q "Claude Supercharger" ~/.claude/CLAUDE.md 2>/dev/null && echo "FAIL: block not removed" || echo "OK: block removed"
```

- [ ] **Step 8: Restore original ~/.claude/**

```bash
cp -r /tmp/claude-backup-test/* ~/.claude/
rm -rf /tmp/claude-backup-test/
```

- [ ] **Step 9: Commit test results (if any fixes were needed)**

```bash
git add -A
git commit -m "fix: integration test fixes"
```

---

## Task Summary

| Task | Description | Files | Depends On |
|---|---|---|---|
| 1 | Clean up old content | Remove 11+ files/dirs | — |
| 2 | Create directory structure | 4 directories | Task 1 |
| 3 | Universal configs | 3 markdown files | Task 2 |
| 4 | Role overlays | 5 markdown files | Task 2 |
| 5 | Hook scripts | 6 shell scripts | Task 2 |
| 6 | lib/utils.sh | 1 file | Task 2 |
| 7 | lib/backup.sh | 1 file | Task 6 |
| 8 | lib/roles.sh | 1 file | Task 6 |
| 9 | lib/hooks.sh | 1 file | Task 6 |
| 10 | lib/extras.sh | 1 file | Task 6 |
| 11 | tools/claude-check.sh | 1 file | Task 2 |
| 12 | install.sh | 1 file | Tasks 6-10 |
| 13 | uninstall.sh | 1 file | Task 6 |
| 14 | README.md | 1 file | Tasks 1-13 |
| 15 | LICENSE + CHANGELOG | 2 files | Tasks 1-13 |
| 16 | .gitignore | 1 file | — |
| 17 | Integration test | 0 files | Tasks 1-16 |

**Parallelizable:** Tasks 3, 4, 5, 11 can run in parallel (independent content). Tasks 6-10 must be sequential (lib/ dependencies). Task 12 depends on all lib/ tasks. Task 17 depends on everything.

**Total: 17 tasks, ~35 files, ~380 lines of shell, ~300 lines of markdown configs**
