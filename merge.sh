#!/usr/bin/env bash
set -euo pipefail
umask 077

# Claude Supercharger v1.0.0 Merge Script
# Smart merge for existing configurations
# Note: No integrity/checksum verification of source files

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}╔══════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  Claude Supercharger v1.0.0 Merge      ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════╝${NC}"
echo ""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="$HOME/.claude/backups/merge-$(date +%Y%m%d-%H%M%S)"

# Create backup (only .md and shared/ — avoids copying sensitive files)
echo -e "${BLUE}📦 Creating backup at $BACKUP_DIR${NC}"
mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"
if [ -d "$HOME/.claude" ]; then
    cp "$HOME/.claude/"*.md "$BACKUP_DIR/" 2>/dev/null || true
    [ -d "$HOME/.claude/shared" ] && cp -r "$HOME/.claude/shared" "$BACKUP_DIR/" 2>/dev/null || true
fi
echo -e "${GREEN}✓ Backup created${NC}"
echo ""

# Check existing configuration
echo -e "${BLUE}🔍 Detecting existing configuration...${NC}"
HAS_CLAUDE_MD=false
HAS_RULES_MD=false
HAS_MCP_MD=false
HAS_PERSONAS_MD=false
HAS_SHARED=false

[ -f "$HOME/.claude/CLAUDE.md" ] && HAS_CLAUDE_MD=true
[ -f "$HOME/.claude/RULES.md" ] && HAS_RULES_MD=true
[ -f "$HOME/.claude/MCP.md" ] && HAS_MCP_MD=true
[ -f "$HOME/.claude/PERSONAS.md" ] && HAS_PERSONAS_MD=true
[ -d "$HOME/.claude/shared" ] && HAS_SHARED=true

if [ "$HAS_CLAUDE_MD" = false ] && [ "$HAS_RULES_MD" = false ]; then
    echo -e "${YELLOW}⚠️  No existing configuration found. Use install.sh instead.${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Existing configuration detected${NC}"
echo ""

# Merge CLAUDE.md
if [ "$HAS_CLAUDE_MD" = true ]; then
    echo -e "${BLUE}🔧 Merging CLAUDE.md...${NC}"

    # Check if already has Supercharger markers
    if grep -q "Claude Supercharger v1.0.0" "$HOME/.claude/CLAUDE.md" 2>/dev/null; then
        echo -e "${YELLOW}  ⚠️  Claude Supercharger already integrated in CLAUDE.md${NC}"
    else
        # Append Supercharger integration marker
        cat >> "$HOME/.claude/CLAUDE.md" << 'EOF'

# ═══════════════════════════════════════
# Claude Supercharger v1.0.0 Integration
# ═══════════════════════════════════════

@RULES.md
@MCP.md
@PERSONAS.md
EOF
        echo -e "${GREEN}  ✓ Added Supercharger integration to CLAUDE.md${NC}"
    fi
else
    cp "$SCRIPT_DIR/core/CLAUDE.md" "$HOME/.claude/"
    echo -e "${GREEN}  ✓ Installed CLAUDE.md${NC}"
fi

# Merge RULES.md
if [ "$HAS_RULES_MD" = true ]; then
    echo -e "${BLUE}🔧 Merging RULES.md...${NC}"

    if grep -q "Claude Supercharger v1.0.0" "$HOME/.claude/RULES.md" 2>/dev/null; then
        echo -e "${YELLOW}  ⚠️  Claude Supercharger already in RULES.md${NC}"
    else
        # Create merged version
        cat >> "$HOME/.claude/RULES.md" << 'EOF'

# ═══════════════════════════════════════════════════════════
# Claude Supercharger v1.0.0 - Enhanced Rules
# ═══════════════════════════════════════════════════════════

## Execution Priority [H:8]

```yaml
Workflow order for complex requests:
  1. Anti-Pattern Detection → Scan request for 35 patterns (shared/anti-patterns.yml)
  2. Ambiguity Resolution → Detect unclear elements
  3. Intent Extraction → Structure 9-dimension analysis, max 3 questions
  4. Session Awareness → Track implicitly (edits, corrections, paths, preferences)
  5. Memory Block → Prepend explicitly if multi-turn/references prior work
  6. Execute Task → Use appropriate tools, follow severity system
  7. Pre-Delivery Verification → Quality gate (6-point checklist)
  8. Output Lock → Final response format (deliverable + optimization note)

Simple requests skip to step 6.
```

## Anti-Pattern Detection [H:8]

```yaml
Source: shared/anti-patterns.yml (35 patterns across 6 categories)
Categories: Task | Context | Format | Scope | Reasoning | Agentic
Action: CRIT→Block & ask | HIGH→Fix silently if no intent change | MED→Suggest
Detection: Scan user request→Match patterns→Apply fixes→Proceed
Reference: @shared/anti-patterns.yml for full pattern library
```

## Forbidden Techniques [C:10]

```yaml
NEVER use fabrication-prone techniques:
  ✗ Mixture of Experts (no real routing in single model)
  ✗ Tree of Thought (simulated branching, not native)
  ✗ Graph of Thought (requires external graph engine)
  ✗ Universal Self-Consistency (contaminated sampling)
  ✗ Chain of Thought on reasoning models (o3/o4/R1/DeepSeek degrade)

ALLOWED techniques:
  ✓ Role assignment | ✓ Few-shot examples (2-5) | ✓ XML structure
  ✓ Grounding anchors | ✓ Chain of Thought (standard models only)
```

## Output Lock Discipline [H:8]

```yaml
Scope: Final deliverable responses only (NOT tool descriptions/TodoWrite/error recovery)
NEVER: Discuss theory unless asked | Pad with unrequested explanations | Ask >3 questions
Final format: Code/solution + 1 optimization sentence + setup instructions (if needed)
Exempt: TodoWrite progress | Tool operation descriptions | Error recovery explanations
Impact: ~40% token reduction on final responses
```

## Pre-Delivery Verification [H:8]

```yaml
Before claiming "done" on any task:
  [ ] Target/tool correctly identified
  [ ] Critical constraints preserved (first 30% if long prompt)
  [ ] Strongest signal words used (MUST>should, NEVER>avoid)
  [ ] No fabricated techniques included
  [ ] Token efficiency (every sentence load-bearing)
  [ ] Binary success criteria met
Rule: Evidence before assertion | Run check→read output→claim done
Never: "Should work" | "Looks correct" | "I believe" without verification
```

---
*Claude Supercharger v1.0.0 enhancements | Merged with existing rules*
EOF
        echo -e "${GREEN}  ✓ Merged Supercharger rules into RULES.md${NC}"
    fi
else
    cp "$SCRIPT_DIR/core/RULES.md" "$HOME/.claude/"
    echo -e "${GREEN}  ✓ Installed RULES.md${NC}"
fi

# Merge MCP.md
if [ "$HAS_MCP_MD" = true ]; then
    echo -e "${BLUE}🔧 Merging MCP.md...${NC}"

    if grep -q "Tool-Specific Optimization" "$HOME/.claude/MCP.md" 2>/dev/null; then
        echo -e "${YELLOW}  ⚠️  Tool-Specific Optimization already in MCP.md${NC}"
    else
        cat >> "$HOME/.claude/MCP.md" << 'EOF'

# ═══════════════════════════════════════════════════════════
# Claude Supercharger v1.0.0 - Tool-Specific Optimization
# ═══════════════════════════════════════════════════════════

## Tool-Specific Optimization [M:6]

```yaml
Claude Opus 4.x:
  - Over-engineers by default → add "Only make changes directly requested"
  - Prevent scope creep on agentic tasks

o3/o4-mini (reasoning models):
  - SHORT clean instructions ONLY
  - NEVER add CoT (degrades output)
  - System prompts <200 words

GPT-5.x:
  - Compact structured outputs
  - Constrain verbosity: "Under 150 words. No preamble."

Gemini 2.x/3 Pro:
  - Prone to hallucinated citations → "Cite only certain sources. If uncertain, say [uncertain]."
  - Grounded tasks: "Base response only on provided context."

DeepSeek-R1:
  - Reasoning-native → SHORT instructions, no CoT
  - Outputs in <think> tags → "Output only final answer" if needed

Qwen / Ollama / Local models:
  - Model-specific guidance
  - Shorter simpler prompts
  - Temperature recommendations
```

---
*Claude Supercharger v1.0.0 enhancements | Merged with existing MCP config*
EOF
        echo -e "${GREEN}  ✓ Merged Tool-Specific Optimization into MCP.md${NC}"
    fi
else
    cp "$SCRIPT_DIR/core/MCP.md" "$HOME/.claude/"
    echo -e "${GREEN}  ✓ Installed MCP.md${NC}"
fi

# Merge PERSONAS.md
if [ "$HAS_PERSONAS_MD" = true ]; then
    echo -e "${BLUE}🔧 Merging PERSONAS.md...${NC}"

    # Check if Supercharger personas already exist
    EXISTING_PERSONAS=$(grep -cE "^### (architect|frontend|backend|analyzer|security|mentor|refactorer|performance|qa)$" "$HOME/.claude/PERSONAS.md" 2>/dev/null || echo 0)
    EXISTING_PERSONAS=$((EXISTING_PERSONAS + 0))

    if [ "$EXISTING_PERSONAS" -ge 5 ]; then
        echo -e "${YELLOW}  ⚠️  Similar personas already exist (found $EXISTING_PERSONAS)${NC}"
        echo -e "${YELLOW}  ⚠️  Skipping to avoid duplicates. See docs/MIGRATION.md to merge manually.${NC}"
    else
        echo -e "${YELLOW}  ⚠️  Custom PERSONAS.md detected${NC}"
        echo -e "${YELLOW}  ⚠️  Installing Supercharger personas to ~/.claude/shared/supercharger-personas.md${NC}"
        mkdir -p "$HOME/.claude/shared"
        cp "$SCRIPT_DIR/core/PERSONAS.md" "$HOME/.claude/shared/supercharger-personas.md"

        # Add reference in existing PERSONAS.md
        if ! grep -q "supercharger-personas.md" "$HOME/.claude/PERSONAS.md" 2>/dev/null; then
            cat >> "$HOME/.claude/PERSONAS.md" << 'EOF'

# ═══════════════════════════════════════
# Claude Supercharger Personas
# ═══════════════════════════════════════
# Reference: ~/.claude/shared/supercharger-personas.md
# Includes: architect, frontend, backend, analyzer, security, mentor, refactorer, performance, qa
EOF
        fi
        echo -e "${GREEN}  ✓ Installed to shared/supercharger-personas.md${NC}"
    fi
else
    cp "$SCRIPT_DIR/core/PERSONAS.md" "$HOME/.claude/"
    echo -e "${GREEN}  ✓ Installed PERSONAS.md${NC}"
fi

# Install shared resources
echo -e "${BLUE}🔧 Installing shared resources...${NC}"
mkdir -p "$HOME/.claude/shared"

if [ -f "$HOME/.claude/shared/anti-patterns.yml" ]; then
    echo -e "${YELLOW}  ⚠️  anti-patterns.yml already exists${NC}"
else
    cp "$SCRIPT_DIR/shared/anti-patterns.yml" "$HOME/.claude/shared/"
    echo -e "${GREEN}  ✓ Installed anti-patterns.yml${NC}"
fi

# Success message
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║     ✓ Merge Completed!                  ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}Claude Supercharger v1.0.0 merged with your existing configuration.${NC}"
echo ""
echo -e "${YELLOW}What was merged:${NC}"
echo "  • 35 Anti-Pattern Detection"
echo "  • Execution Priority workflow"
echo "  • Pre-Delivery Verification"
echo "  • Output Lock Discipline"
echo "  • Tool-Specific Optimization"
echo "  • Forbidden Techniques list"
echo ""
echo -e "${BLUE}Your custom configuration was preserved and enhanced.${NC}"
echo ""
echo -e "${YELLOW}Backup location: $BACKUP_DIR${NC}"
echo -e "${YELLOW}Migration guide: $SCRIPT_DIR/docs/MIGRATION.md${NC}"
echo -e "${YELLOW}Restore backup: bash $SCRIPT_DIR/uninstall.sh${NC}"
echo ""
