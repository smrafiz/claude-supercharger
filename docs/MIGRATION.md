# Migration Guide

How to integrate Claude Supercharger v1.0.0 with existing Claude Code configurations.

---

## Table of Contents

1. [Installation Modes](#installation-modes)
2. [Conflict Resolution](#conflict-resolution)
3. [Cherry-Picking Features](#cherry-picking-features)
4. [Manual Merge Steps](#manual-merge-steps)
5. [Troubleshooting](#troubleshooting)

---

## Installation Modes

### Fresh Install (Replace Everything)

**Use when:** Starting from scratch or want complete replacement.

```bash
bash install.sh
```

- ✓ Backs up existing config to `~/.claude/backups/`
- ✓ Installs all Supercharger files
- ⚠️ Replaces all existing configuration

---

### Smart Merge (Preserve + Enhance)

**Use when:** Have custom configurations you want to keep.

```bash
bash merge.sh
```

- ✓ Backs up existing config
- ✓ Detects existing files
- ✓ Appends Supercharger enhancements
- ✓ Preserves your custom rules/personas
- ⚠️ May create duplicates if similar content exists

---

### Manual Cherry-Pick (Full Control)

**Use when:** Want to selectively integrate specific features.

See [Cherry-Picking Features](#cherry-picking-features) below.

---

## Conflict Resolution

### Scenario 1: Duplicate Rules

**Problem:** Your RULES.md already has severity system (CRITICAL/HIGH/MEDIUM).

**Solution:**
1. Open `~/.claude/RULES.md`
2. Find your existing severity section
3. Add Supercharger enhancements only:
   ```markdown
   ## Execution Priority [H:8]
   # ... copy from core/RULES.md lines 21-30

   ## Anti-Pattern Detection [H:8]
   # ... copy from core/RULES.md lines 32-39
   ```
4. Skip duplicate sections

---

### Scenario 2: Conflicting Personas

**Problem:** You already have an `architect` persona with different behavior.

**Solutions:**

**Option A: Rename Supercharger personas**
```yaml
# In ~/.claude/PERSONAS.md
### architect_sc  # Your original
### architect_supercharger  # Supercharger version
```

**Option B: Merge behaviors**
```yaml
### architect
Core_Belief: [Your belief] + Systems evolve, design for change
Decision_Pattern: [Your pattern] + Long-term maintainability > short-term efficiency
# ... combine both definitions
```

**Option C: Keep separate**
```bash
# Your personas: ~/.claude/PERSONAS.md
# Supercharger personas: ~/.claude/shared/supercharger-personas.md
# Reference both in CLAUDE.md:
@PERSONAS.md
@shared/supercharger-personas.md
```

---

### Scenario 3: Different MCP Configuration

**Problem:** Your MCP.md uses different server names or configuration structure.

**Solution:**
1. Keep your existing MCP configuration intact
2. Add only the Tool-Specific Optimization section:
   ```markdown
   ## Tool-Specific Optimization [M:6]
   # ... copy from core/MCP.md lines 120-150
   ```
3. Adjust server names to match yours

---

### Scenario 4: Custom Thinking Modes

**Problem:** Your CLAUDE.md has custom thinking mode triggers.

**Solution:**
```yaml
# Merge both systems
Thinking Modes:
  # Your custom modes
  deep-dive: Comprehensive analysis
  quick: Fast responses

  # Supercharger modes
  think: Multi-file 4K
  think-hard: Architecture 10K
  ultrathink: Critical 32K
```

---

## Cherry-Picking Features

Select only the features you want:

### Feature 1: Anti-Pattern Detection

**Files needed:**
- `shared/anti-patterns.yml` → `~/.claude/shared/anti-patterns.yml`
- Add to RULES.md:
```yaml
## Anti-Pattern Detection [H:8]
Source: shared/anti-patterns.yml (35 patterns across 6 categories)
Categories: Task | Context | Format | Scope | Reasoning | Agentic
Action: CRIT→Block & ask | HIGH→Fix silently if no intent change | MED→Suggest
```

---

### Feature 2: Execution Priority Workflow

**Add to RULES.md:**
```yaml
## Execution Priority [H:8]
Workflow order for complex requests:
  1. Anti-Pattern Detection → Scan request for 35 patterns
  2. Ambiguity Resolution → Detect unclear elements
  3. Intent Extraction → 9-dimension analysis, max 3 questions
  4. Session Awareness → Track implicitly
  5. Memory Block → Prepend explicitly if multi-turn
  6. Execute Task → Use appropriate tools
  7. Pre-Delivery Verification → Quality gate
  8. Output Lock → Final response format
```

---

### Feature 3: Pre-Delivery Verification

**Add to RULES.md:**
```yaml
## Pre-Delivery Verification [H:8]
Before claiming "done":
  [ ] Target/tool correctly identified
  [ ] Critical constraints preserved
  [ ] Strongest signal words used (MUST>should, NEVER>avoid)
  [ ] No fabricated techniques
  [ ] Token efficiency (every sentence load-bearing)
  [ ] Binary success criteria met
```

---

### Feature 4: Output Lock Discipline

**Add to RULES.md:**
```yaml
## Output Lock Discipline [H:8]
NEVER: Discuss theory unless asked | Pad output | Ask >3 questions
Final format: Code/solution + 1 optimization sentence + setup (if needed)
Exempt: TodoWrite | Tool descriptions | Error recovery
```

---

### Feature 5: Tool-Specific Optimization

**Add to MCP.md:**
```yaml
## Tool-Specific Optimization [M:6]
Claude Opus 4.x: Add "Only make changes directly requested"
o3/o4-mini: SHORT instructions, no CoT, <200 words
GPT-5.x: Compact outputs, "Under 150 words. No preamble."
Gemini: "Cite only certain sources. If uncertain, say [uncertain]."
DeepSeek-R1: SHORT instructions, no CoT, reasoning-native
```

---

### Feature 6: Forbidden Techniques

**Add to RULES.md:**
```yaml
## Forbidden Techniques [C:10]
NEVER use:
  ✗ Mixture of Experts | ✗ Tree of Thought | ✗ Graph of Thought
  ✗ Universal Self-Consistency | ✗ CoT on reasoning models
ALLOWED:
  ✓ Role assignment | ✓ Few-shot (2-5) | ✓ XML | ✓ Grounding | ✓ CoT (standard models)
```

---

### Feature 7: Memory Block Template

**Add to RULES.md Session Awareness section:**
```yaml
Memory Block Template:
  Trigger: User references prior work | Multi-turn complex tasks
  Template:
    ## Context (carry forward)
    - Stack & tool decisions: [list]
    - Architecture choices locked: [list]
    - Constraints from prior turns: [list]
    - What was tried & failed: [list]
```

---

### Feature 8: Cognitive Personas

**Options:**

**Full Install:**
```bash
cp core/PERSONAS.md ~/.claude/PERSONAS.md
```

**Selective Install (pick personas):**
```yaml
# Copy only desired personas from core/PERSONAS.md
# Available: architect, frontend, backend, analyzer, security,
#            mentor, refactorer, performance, qa
```

---

## Manual Merge Steps

### Step 1: Backup Current Configuration

```bash
BACKUP_DIR=~/.claude/backups/manual-$(date +%Y%m%d-%H%M%S)
mkdir -p "$BACKUP_DIR"
cp -r ~/.claude/* "$BACKUP_DIR/"
echo "Backup created at $BACKUP_DIR"
```

---

### Step 2: Review Differences

```bash
# Compare your RULES.md with Supercharger version
diff ~/.claude/RULES.md core/RULES.md

# Compare PERSONAS.md
diff ~/.claude/PERSONAS.md core/PERSONAS.md

# Compare MCP.md
diff ~/.claude/MCP.md core/MCP.md
```

---

### Step 3: Selective Copy

**Example: Add Anti-Pattern Detection only**

```bash
# Install anti-patterns library
mkdir -p ~/.claude/shared
cp shared/anti-patterns.yml ~/.claude/shared/

# Add reference to RULES.md
cat >> ~/.claude/RULES.md << 'EOF'

## Anti-Pattern Detection [H:8]
Source: shared/anti-patterns.yml (35 patterns)
Categories: Task | Context | Format | Scope | Reasoning | Agentic
Action: CRIT→Block | HIGH→Fix silently | MED→Suggest
EOF
```

---

### Step 4: Test Integration

```bash
# Verify files exist
ls -la ~/.claude/
ls -la ~/.claude/shared/

# Check for syntax errors
grep -E "CRITICAL|HIGH|MEDIUM" ~/.claude/RULES.md

# Test anti-pattern detection
grep "anti-patterns.yml" ~/.claude/RULES.md
```

---

### Step 5: Validate in Claude Code

1. Restart Claude Code
2. Test vague request: "fix the bug"
3. Verify anti-pattern detection triggers
4. Test persona: `/persona:architect`
5. Check memory block on multi-turn tasks

---

## Troubleshooting

### Problem: Duplicate Sections After Merge

**Symptoms:** Multiple "## Anti-Pattern Detection" headings in RULES.md

**Solution:**
```bash
# Restore backup
cp ~/.claude/backups/[latest]/* ~/.claude/

# Use manual cherry-pick instead of merge.sh
```

---

### Problem: Personas Not Activating

**Symptoms:** `/persona:architect` doesn't change behavior

**Check:**
1. PERSONAS.md exists: `ls ~/.claude/PERSONAS.md`
2. Referenced in CLAUDE.md: `grep PERSONAS ~/.claude/CLAUDE.md`
3. Persona defined: `grep "### architect" ~/.claude/PERSONAS.md`

**Fix:**
```bash
# Ensure CLAUDE.md references PERSONAS.md
echo "@PERSONAS.md" >> ~/.claude/CLAUDE.md
```

---

### Problem: Anti-Patterns Not Triggering

**Check:**
1. File exists: `ls ~/.claude/shared/anti-patterns.yml`
2. Referenced in RULES.md: `grep "anti-patterns.yml" ~/.claude/RULES.md`
3. Anti-Pattern Detection section exists in RULES.md

**Fix:**
```bash
cp shared/anti-patterns.yml ~/.claude/shared/
# Add reference to RULES.md manually (see Step 3 above)
```

---

### Problem: Conflicting MCP Configurations

**Symptoms:** MCP servers not connecting, duplicate tool calls

**Solution:**
1. Keep ONE primary MCP.md
2. If merging, ensure server names don't conflict:
   ```yaml
   # Your config
   context7: ...

   # Supercharger adds tool-specific optimization, not new servers
   Tool-Specific Optimization: [add this section only]
   ```

---

### Problem: Installation Script Fails

**Error:** "Claude Supercharger already integrated"

**Meaning:** Supercharger already installed or partially merged

**Options:**
1. Fresh reinstall: `bash uninstall.sh` then `bash install.sh`
2. Manual review: Check which files have "Claude Supercharger v1.0.0" marker
3. Skip: Configuration already integrated

---

## Restore Backup

If merge causes issues:

```bash
# List backups
ls -la ~/.claude/backups/

# Restore specific backup
BACKUP_DIR=~/.claude/backups/[timestamp]
cp -r "$BACKUP_DIR"/* ~/.claude/

# Verify restoration
grep "Claude Supercharger" ~/.claude/RULES.md || echo "Backup restored"
```

---

## Best Practices

1. **Always backup first** before any merge
2. **Test incrementally**: Add one feature at a time
3. **Review diffs**: Understand what's changing
4. **Keep backups**: Don't delete old backups immediately
5. **Document changes**: Note what you customized
6. **Version your config**: Use git for ~/.claude/ directory

---

## Feature Compatibility Matrix

| Your Config Has | Supercharger Adds | Conflict? | Solution |
|----------------|-------------------|-----------|----------|
| Severity system | Enhanced severity + anti-patterns | Low | Append |
| Custom personas | 9 new personas | Medium | Rename or merge |
| MCP config | Tool-specific optimization | Low | Append section |
| Thinking modes | Execution priority workflow | Low | Add workflow |
| Session tracking | Memory block template | Low | Add template |
| Custom rules | Forbidden techniques | Low | Append |
| Output formatting | Output lock discipline | Medium | Merge rules |

---

## Getting Help

- **GitHub Issues:** https://github.com/smrafiz/claude-supercharger/issues
- **Review backups:** `~/.claude/backups/`
- **Compare files:** `diff ~/.claude/RULES.md core/RULES.md`
- **Uninstall:** `bash uninstall.sh`

---

*Claude Supercharger v1.0.0 | Migration flexibility for existing configurations*
