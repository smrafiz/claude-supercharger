# Token Economy v2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the flat token economy with a tiered system (Standard/Lean/Minimal) featuring per-output-type calibration, role-aware constraints, and user-selectable verbosity at install time and mid-conversation.

**Architecture:** A single `economy.md` rule file holds universal output rules + the active tier definition. Three tier template files live in `~/.claude/supercharger/economy/` for post-install switching. Role files declare their default tier and floor/ceiling constraints. A new `lib/economy.sh` handles tier selection, validation, and deployment. A `tools/economy-switch.sh` CLI enables post-install tier changes.

**Tech Stack:** Bash, Python 3 (JSON ops), Claude Code rules system (`~/.claude/rules/`)

---

### Task 1: Create Economy Tier Template Files

**Files:**
- Create: `configs/economy/standard.md`
- Create: `configs/economy/lean.md`
- Create: `configs/economy/minimal.md`

- [ ] **Step 1: Create the configs/economy/ directory**

```bash
mkdir -p configs/economy
```

- [ ] **Step 2: Create standard.md**

```bash
cat > configs/economy/standard.md << 'EOF'
### Active Tier: Standard (~30% reduction)
Concise, natural English. Complete sentences. No filler, but readable.

- **Code**: Full implementation with filename context. No inline comments.
- **Commands**: Command with one-line purpose if non-obvious.
- **Explanation**: Clear paragraphs, max 3 per response. Analogies welcome.
- **Diagnosis**: What failed, why, fix — up to 5 lines.
- **Coordination**: Full sentences, structured with bullets. Max 8 lines.
EOF
```

- [ ] **Step 3: Create lean.md**

```bash
cat > configs/economy/lean.md << 'EOF'
### Active Tier: Lean (~45% reduction)
Every word load-bearing. Fragments OK. Deliver, don't narrate.

- **Code**: Diff or block only. Filename as header, no surrounding text.
- **Commands**: Bare command. No wrapper, no "I'll run...".
- **Explanation**: Bullets only. One concept per bullet. Max 8 bullets.
- **Diagnosis**: What → why → fix. Three lines max.
- **Coordination**: Bullets, no prose. Max 5 lines.
EOF
```

- [ ] **Step 4: Create minimal.md**

```bash
cat > configs/economy/minimal.md << 'EOF'
### Active Tier: Minimal (~60% reduction)
Telegraphic. Bare deliverables. Context only when ambiguity is dangerous.

- **Code**: Block only. No filename unless multiple files in response.
- **Commands**: Command only. Zero surrounding text.
- **Explanation**: Shortest accurate form. Fragments, abbreviations OK. Max 4 bullets.
- **Diagnosis**: One-line: [what failed] → [fix]. Two lines if cause is non-obvious.
- **Coordination**: Terse fragments. Max 3 lines.
EOF
```

- [ ] **Step 5: Commit**

```bash
git add configs/economy/standard.md configs/economy/lean.md configs/economy/minimal.md
git commit -m "feat: add economy tier template files (standard/lean/minimal)"
```

---

### Task 2: Create economy.md Universal Rule File

**Files:**
- Create: `configs/universal/economy.md`

- [ ] **Step 1: Create economy.md with universal rules, output types, all tier definitions, and switching keywords**

```bash
cat > configs/universal/economy.md << 'ECONOMY'
# Token Economy — Claude Supercharger

## Universal Output Rules
These apply at every tier and cannot be overridden:

1. Lead with the deliverable — code, answer, or action. Not the reasoning.
2. Never restate the user's request or summarize what you just did.
3. No ceremony: skip "Here's what I found", "Let me explain", "I'll now...", "Happy to help".
4. One completion per turn — no unsolicited alternatives.
5. If the answer is yes or no, say that. Not a paragraph.
6. Lists over prose. Tables over lists. Bare output over wrapped output.
7. Clarifying questions: max 3, one per message when possible.

## Output Types
All responses fall into one of these types. Tier modifiers set expectations per type.

- **Code** — generated code blocks, diffs, implementations, file contents
- **Commands** — shell commands, git operations, tool invocations
- **Explanation** — teaching, reasoning, "why", architecture discussion
- **Diagnosis** — errors, status, what happened, what to do next
- **Coordination** — planning, clarifying questions, scope negotiation, handoff summaries

Classification rules:
- If a response mixes types, each section follows its own type's rules
- When in doubt, treat it as the shorter type

## Economy Tiers

{{ACTIVE_TIER}}

## Role Constraints
Each role declares a default tier and allowed range (floor–ceiling).
When multiple roles are active, the most restrictive floor wins.

| Role          | Default  | Range              |
|---------------|----------|--------------------|
| Developer     | Lean     | unrestricted       |
| Student       | Standard | Standard–Lean      |
| Writer        | Standard | Standard–unlimited |
| Data Analyst  | Lean     | unrestricted       |
| PM            | Lean     | unrestricted       |

If a selected tier falls outside the active role's range, it auto-corrects to the nearest allowed tier.

## Mid-Conversation Switching

Say any of these to change tier during a conversation:
- "eco standard" → Standard tier
- "eco lean" → Lean tier
- "eco minimal" → Minimal tier

Can combine with role switch: "as student eco standard"

Switching is session-only. For permanent changes, run:
  bash tools/economy-switch.sh [standard|lean|minimal]
ECONOMY
```

- [ ] **Step 2: Verify the file reads correctly**

```bash
cat configs/universal/economy.md
```

Expected: File contents as above with `{{ACTIVE_TIER}}` placeholder visible.

- [ ] **Step 3: Commit**

```bash
git add configs/universal/economy.md
git commit -m "feat: add economy.md universal token economy rule file"
```

---

### Task 3: Create lib/economy.sh

**Files:**
- Create: `lib/economy.sh`

- [ ] **Step 1: Write the economy library with tier selection, validation, and deployment functions**

```bash
cat > lib/economy.sh << 'LIBECONOMY'
#!/usr/bin/env bash
# Claude Supercharger — Economy Tier Selection & Deployment

AVAILABLE_TIERS=("standard" "lean" "minimal")
TIER_LABELS=(
  "Standard  — concise, natural English (~30% reduction)"
  "Lean      — every word earns its place (~45% reduction)"
  "Minimal   — telegraphic, bare output (~60% reduction)"
)
DEFAULT_TIER="lean"
SELECTED_TIER=""

# Role constraints: role|default|floor|ceiling
# Empty floor/ceiling = unrestricted
ROLE_CONSTRAINTS=(
  "developer|lean||"
  "student|standard|standard|lean"
  "writer|standard|standard|"
  "data|lean||"
  "pm|lean||"
)

# Map tier name to numeric rank for comparison
tier_rank() {
  case "$1" in
    standard) echo 1 ;;
    lean)     echo 2 ;;
    minimal)  echo 3 ;;
    *)        echo 0 ;;
  esac
}

# Map numeric rank back to tier name
rank_to_tier() {
  case "$1" in
    1) echo "standard" ;;
    2) echo "lean" ;;
    3) echo "minimal" ;;
    *) echo "lean" ;;
  esac
}

# Get the default tier for selected roles (most restrictive default)
get_default_tier_for_roles() {
  local roles="$1"
  local most_restrictive_rank=3  # start at minimal (least restrictive)

  for constraint in "${ROLE_CONSTRAINTS[@]}"; do
    IFS='|' read -r role default floor ceiling <<< "$constraint"
    if echo "$roles" | grep -q "$role"; then
      local rank
      rank=$(tier_rank "$default")
      if [ "$rank" -lt "$most_restrictive_rank" ]; then
        most_restrictive_rank=$rank
      fi
    fi
  done

  rank_to_tier "$most_restrictive_rank"
}

# Get the floor for selected roles (most restrictive floor)
get_floor_for_roles() {
  local roles="$1"
  local highest_floor=0  # no floor

  for constraint in "${ROLE_CONSTRAINTS[@]}"; do
    IFS='|' read -r role default floor ceiling <<< "$constraint"
    if echo "$roles" | grep -q "$role"; then
      if [ -n "$floor" ]; then
        local rank
        rank=$(tier_rank "$floor")
        if [ "$rank" -gt "$highest_floor" ]; then
          highest_floor=$rank
        fi
      fi
    fi
  done

  if [ "$highest_floor" -eq 0 ]; then
    echo ""
  else
    rank_to_tier "$highest_floor"
  fi
}

# Get the ceiling for selected roles (most restrictive ceiling)
get_ceiling_for_roles() {
  local roles="$1"
  local lowest_ceiling=4  # no ceiling (above minimal)

  for constraint in "${ROLE_CONSTRAINTS[@]}"; do
    IFS='|' read -r role default floor ceiling <<< "$constraint"
    if echo "$roles" | grep -q "$role"; then
      if [ -n "$ceiling" ]; then
        local rank
        rank=$(tier_rank "$ceiling")
        if [ "$rank" -lt "$lowest_ceiling" ]; then
          lowest_ceiling=$rank
        fi
      fi
    fi
  done

  if [ "$lowest_ceiling" -eq 4 ]; then
    echo ""
  else
    rank_to_tier "$lowest_ceiling"
  fi
}

# Validate tier against role constraints, return corrected tier
validate_tier_for_roles() {
  local tier="$1"
  local roles="$2"
  local tier_r
  tier_r=$(tier_rank "$tier")

  local floor
  floor=$(get_floor_for_roles "$roles")
  if [ -n "$floor" ]; then
    local floor_r
    floor_r=$(tier_rank "$floor")
    if [ "$tier_r" -gt "$floor_r" ]; then
      # tier is more aggressive than floor allows
      warn "$(capitalize "$tier") is below the floor for your roles. Setting to $(capitalize "$floor")."
      echo "$floor"
      return
    fi
  fi

  local ceiling
  ceiling=$(get_ceiling_for_roles "$roles")
  if [ -n "$ceiling" ]; then
    local ceiling_r
    ceiling_r=$(tier_rank "$ceiling")
    if [ "$tier_r" -lt "$ceiling_r" ]; then
      # tier is more verbose than ceiling allows — this shouldn't happen
      # with current constraints but handles future additions
      warn "$(capitalize "$tier") exceeds the ceiling for your roles. Setting to $(capitalize "$ceiling")."
      echo "$ceiling"
      return
    fi
  fi

  echo "$tier"
}

capitalize() {
  echo "$(echo "${1:0:1}" | tr '[:lower:]' '[:upper:]')${1:1}"
}

# Interactive tier selection
select_economy_tier() {
  local roles="$1"

  local default_for_roles
  default_for_roles=$(get_default_tier_for_roles "$roles")

  echo ""
  info "Select token economy tier:"
  echo ""
  for i in "${!AVAILABLE_TIERS[@]}"; do
    local marker=""
    if [[ "${AVAILABLE_TIERS[$i]}" == "$default_for_roles" ]]; then
      marker=" [default]"
    fi
    echo -e "  ${BOLD}$((i+1)))${NC} ${TIER_LABELS[$i]}${marker}"
  done
  echo ""

  local input
  read -rp "> " input

  if [ -z "$input" ]; then
    SELECTED_TIER="$default_for_roles"
  elif [[ "$input" =~ ^[0-9]+$ ]] && [ "$input" -ge 1 ] && [ "$input" -le 3 ]; then
    SELECTED_TIER="${AVAILABLE_TIERS[$((input-1))]}"
  else
    warn "Invalid selection. Defaulting to $(capitalize "$default_for_roles")."
    SELECTED_TIER="$default_for_roles"
  fi

  # Validate against role constraints
  SELECTED_TIER=$(validate_tier_for_roles "$SELECTED_TIER" "$roles")
}

# Deploy economy.md with the selected tier baked in
deploy_economy() {
  local source_dir="$1"
  local tier="$2"
  local rules_dir="$HOME/.claude/rules"
  local economy_dir="$HOME/.claude/supercharger/economy"
  mkdir -p "$rules_dir"
  mkdir -p "$economy_dir"

  # Copy all tier templates to supercharger/economy/ (for switching)
  for t in "${AVAILABLE_TIERS[@]}"; do
    local tier_file="$source_dir/configs/economy/${t}.md"
    if [ -f "$tier_file" ]; then
      cp "$tier_file" "$economy_dir/${t}.md"
    fi
  done

  # Read the selected tier content
  local tier_content=""
  local tier_file="$source_dir/configs/economy/${tier}.md"
  if [ -f "$tier_file" ]; then
    tier_content=$(cat "$tier_file")
  else
    warn "Tier file not found: ${tier}.md. Falling back to lean."
    tier_content=$(cat "$source_dir/configs/economy/lean.md")
  fi

  # Build economy.md with active tier injected
  local economy_template="$source_dir/configs/universal/economy.md"
  if [ -f "$economy_template" ]; then
    # Replace {{ACTIVE_TIER}} placeholder with tier content
    python3 -c "
import sys

with open('$economy_template', 'r') as f:
    template = f.read()

tier_content = '''$tier_content'''

result = template.replace('{{ACTIVE_TIER}}', tier_content)

with open('$rules_dir/economy.md', 'w') as f:
    f.write(result)
"
  fi

  success "Token economy installed ($(capitalize "$tier") tier)"
}

# Get economy constraint lines for a role file
get_role_economy_lines() {
  local role="$1"

  for constraint in "${ROLE_CONSTRAINTS[@]}"; do
    IFS='|' read -r c_role c_default c_floor c_ceiling <<< "$constraint"
    if [[ "$c_role" == "$role" ]]; then
      local range="unrestricted"
      if [ -n "$c_floor" ] && [ -n "$c_ceiling" ]; then
        range="$(capitalize "$c_floor")–$(capitalize "$c_ceiling")"
      elif [ -n "$c_floor" ]; then
        range="$(capitalize "$c_floor")–unrestricted"
      elif [ -n "$c_ceiling" ]; then
        range="unrestricted–$(capitalize "$c_ceiling")"
      fi
      echo "Default economy: $(capitalize "$c_default")"
      echo "Economy range: $range"
      return
    fi
  done

  # Fallback
  echo "Default economy: Lean"
  echo "Economy range: unrestricted"
}
LIBECONOMY
```

- [ ] **Step 2: Verify syntax**

```bash
bash -n lib/economy.sh
```

Expected: No output (clean parse).

- [ ] **Step 3: Commit**

```bash
git add lib/economy.sh
git commit -m "feat: add lib/economy.sh — tier selection, validation, deployment"
```

---

### Task 4: Create tools/economy-switch.sh

**Files:**
- Create: `tools/economy-switch.sh`

- [ ] **Step 1: Write the economy-switch CLI tool**

```bash
cat > tools/economy-switch.sh << 'SWITCHTOOL'
#!/usr/bin/env bash
set -euo pipefail

# Resolve source directory (tools/ → repo root)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

source "$REPO_DIR/lib/utils.sh"
source "$REPO_DIR/lib/economy.sh"

ECONOMY_FILE="$HOME/.claude/rules/economy.md"
ECONOMY_DIR="$HOME/.claude/supercharger/economy"
ROLES_DIR="$HOME/.claude/rules"

show_usage() {
  echo "Usage: economy-switch.sh [standard|lean|minimal]"
  echo ""
  echo "Switches the active token economy tier."
  echo "Takes effect on next Claude Code session."
  exit 0
}

# Get currently active roles from rules/
get_active_roles() {
  local roles=""
  for role in "${AVAILABLE_ROLES[@]:-developer writer student data pm}"; do
    if [ -f "$ROLES_DIR/${role}.md" ]; then
      if [ -n "$roles" ]; then
        roles="$roles,$role"
      else
        roles="$role"
      fi
    fi
  done
  echo "$roles"
}

# --- Main ---
if [ $# -eq 0 ] || [[ "$1" == "--help" ]]; then
  show_usage
fi

TIER=$(echo "$1" | tr '[:upper:]' '[:lower:]')

# Validate tier name
if [[ "$TIER" != "standard" && "$TIER" != "lean" && "$TIER" != "minimal" ]]; then
  error "Unknown tier: $TIER"
  echo "  Valid tiers: standard, lean, minimal"
  exit 1
fi

# Check economy.md exists
if [ ! -f "$ECONOMY_FILE" ]; then
  error "economy.md not found at $ECONOMY_FILE"
  echo "  Run install.sh first."
  exit 1
fi

# Check tier template exists
TIER_FILE="$ECONOMY_DIR/${TIER}.md"
if [ ! -f "$TIER_FILE" ]; then
  error "Tier template not found: $TIER_FILE"
  echo "  Re-run install.sh to restore economy files."
  exit 1
fi

# Validate against active roles
ACTIVE_ROLES=$(get_active_roles)
if [ -n "$ACTIVE_ROLES" ]; then
  VALIDATED_TIER=$(validate_tier_for_roles "$TIER" "$ACTIVE_ROLES")
else
  VALIDATED_TIER="$TIER"
fi

# Read new tier content
NEW_TIER_CONTENT=$(cat "$TIER_FILE")

# Replace active tier block in economy.md
python3 -c "
import re

with open('$ECONOMY_FILE', 'r') as f:
    content = f.read()

# Match from '### Active Tier:' to the next '##' heading or end of file
pattern = r'### Active Tier:.*?(?=\n## |\Z)'
replacement = '''$NEW_TIER_CONTENT'''

result = re.sub(pattern, replacement.strip(), content, count=1, flags=re.DOTALL)

with open('$ECONOMY_FILE', 'w') as f:
    f.write(result)
"

success "Economy tier switched to $(capitalize "$VALIDATED_TIER")"
info "Takes effect on next Claude Code session."
SWITCHTOOL
chmod +x tools/economy-switch.sh
```

- [ ] **Step 2: Verify syntax**

```bash
bash -n tools/economy-switch.sh
```

Expected: No output (clean parse).

- [ ] **Step 3: Commit**

```bash
git add tools/economy-switch.sh
git commit -m "feat: add tools/economy-switch.sh — post-install tier switching CLI"
```

---

### Task 5: Update Role Config Files

**Files:**
- Modify: `configs/roles/developer.md:31-35`
- Modify: `configs/roles/student.md:22-25`
- Modify: `configs/roles/writer.md:20-25`
- Modify: `configs/roles/data.md:20-25`
- Modify: `configs/roles/pm.md:20-25`

- [ ] **Step 1: Write failing test — role files contain economy metadata after deploy**

Create `tests/test-economy.sh`:

```bash
cat > tests/test-economy.sh << 'TESTECONOMY'
#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

source "$REPO_DIR/lib/utils.sh"
source "$REPO_DIR/lib/roles.sh"
source "$REPO_DIR/lib/economy.sh"

# --- Test: developer role has economy metadata ---
begin_test "economy: developer role contains economy metadata"
assert_file_contains "$REPO_DIR/configs/roles/developer.md" "Default economy: Lean" &&
assert_file_contains "$REPO_DIR/configs/roles/developer.md" "Economy range: unrestricted" &&
pass

# --- Test: student role has correct constraints ---
begin_test "economy: student role has Standard floor and Lean ceiling"
assert_file_contains "$REPO_DIR/configs/roles/student.md" "Default economy: Standard" &&
assert_file_contains "$REPO_DIR/configs/roles/student.md" "Economy range: Standard–Lean" &&
pass

# --- Test: writer role has correct constraints ---
begin_test "economy: writer role has Standard floor"
assert_file_contains "$REPO_DIR/configs/roles/writer.md" "Default economy: Standard" &&
assert_file_contains "$REPO_DIR/configs/roles/writer.md" "Economy range: Standard–unrestricted" &&
pass

# --- Test: data role has economy metadata ---
begin_test "economy: data role has economy metadata"
assert_file_contains "$REPO_DIR/configs/roles/data.md" "Default economy: Lean" &&
assert_file_contains "$REPO_DIR/configs/roles/data.md" "Economy range: unrestricted" &&
pass

# --- Test: pm role has economy metadata ---
begin_test "economy: pm role has economy metadata"
assert_file_contains "$REPO_DIR/configs/roles/pm.md" "Default economy: Lean" &&
assert_file_contains "$REPO_DIR/configs/roles/pm.md" "Economy range: unrestricted" &&
pass

report
TESTECONOMY
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
bash tests/test-economy.sh
```

Expected: 5 FAIL (role files don't have economy metadata yet).

- [ ] **Step 3: Update developer.md — replace Token Efficiency section**

Replace lines 31-35 of `configs/roles/developer.md`:

```markdown
## Token Efficiency
- Code blocks only — no surrounding explanation unless asked
- One-line commit messages unless change is multi-faceted
- Error fixes: show the diff, not the reasoning
```

With:

```markdown
## Token Efficiency
Default economy: Lean
Economy range: unrestricted
```

- [ ] **Step 4: Update student.md — replace Token Efficiency section**

Replace lines 22-25 of `configs/roles/student.md`:

```markdown
## Token Efficiency
- Explanations are the product — don't cut them for brevity
- Cap examples at 1 per concept unless asked for more
- After teaching, stop — don't add "you might also want to know..."
```

With:

```markdown
## Token Efficiency
Default economy: Standard
Economy range: Standard–Lean
```

- [ ] **Step 5: Update writer.md — replace Token Efficiency section**

Replace lines 20-25 of `configs/roles/writer.md`:

```markdown
## Token Efficiency
- Draft content at requested length — don't over-deliver
- Meta-discussion (outlines, options, revision notes) stays under 5 lines
- Edits: show the changed text, not a description of what changed
```

With:

```markdown
## Token Efficiency
Default economy: Standard
Economy range: Standard–unrestricted
```

- [ ] **Step 6: Update data.md — replace Token Efficiency section**

Replace lines 20-25 of `configs/roles/data.md`:

```markdown
## Token Efficiency
- Tables and queries are the product — deliver at full fidelity
- Narrative summaries stay under 3 lines
- Methodology notes: 1-2 lines, not paragraphs
```

With:

```markdown
## Token Efficiency
Default economy: Lean
Economy range: unrestricted
```

- [ ] **Step 7: Update pm.md — replace Token Efficiency section**

Replace lines 20-25 of `configs/roles/pm.md`:

```markdown
## Token Efficiency
- Bullet-only output — no prose paragraphs
- Status updates: 3 lines max (done / doing / blocked)
- Decision logs: options | decision | rationale — one line each
```

With:

```markdown
## Token Efficiency
Default economy: Lean
Economy range: unrestricted
```

- [ ] **Step 8: Run the test to verify it passes**

```bash
bash tests/test-economy.sh
```

Expected: 5 PASS.

- [ ] **Step 9: Commit**

```bash
git add configs/roles/*.md tests/test-economy.sh
git commit -m "feat: replace role Token Efficiency sections with economy metadata"
```

---

### Task 6: Update CLAUDE.md Template

**Files:**
- Modify: `configs/universal/CLAUDE.md:12-19`
- Modify: `configs/universal/CLAUDE.md:33-38`

- [ ] **Step 1: Remove the Token Economy section (lines 12-19) and replace with reference**

Replace:

```markdown
## Token Economy
- Responses: 1-3 lines for simple tasks, max 10 lines for complex ones
- Code: no comments, no imports the user can infer, no boilerplate wrappers
- Never repeat back the user's request or restate what you just did
- Lists over prose, tables over lists, symbols over words when meaning is preserved
- One completion per turn — don't offer alternatives unless asked
- Skip: "Here's what I found", "Let me explain", "Great question", preambles, sign-offs
- When asked "did it work?" → "Yes." or "No — [reason]." Not a paragraph.
```

With:

```markdown
## Token Economy
Token economy rules (tiers, output types, switching) are loaded from economy.md.
Switch mid-conversation: "eco standard", "eco lean", or "eco minimal".
```

- [ ] **Step 2: Trim redundant ceremony bullets from Anti-Patterns to Avoid**

Replace:

```markdown
## Anti-Patterns to Avoid
- No ceremonial text ("I'll now proceed to...")
- No unrequested refactoring or scope expansion
- No hallucinated libraries, functions, or flags
- No repeating back what the user just said
- Maximum 3 clarifying questions before proceeding
```

With:

```markdown
## Anti-Patterns to Avoid
- No unrequested refactoring or scope expansion
- No hallucinated libraries, functions, or flags
```

(Ceremony, repeating, and clarification limits are now in economy.md universal rules.)

- [ ] **Step 3: Verify the file still contains critical sections**

```bash
grep -c "Verification Gate\|Safety Boundaries\|Context Management\|Quick Mode Switches" configs/universal/CLAUDE.md
```

Expected: `4` (all four sections still present).

- [ ] **Step 4: Commit**

```bash
git add configs/universal/CLAUDE.md
git commit -m "refactor: move token economy rules to economy.md, trim redundant anti-patterns"
```

---

### Task 7: Update supercharger.md

**Files:**
- Modify: `configs/universal/supercharger.md:27-31`

- [ ] **Step 1: Remove the Output Discipline section**

Replace:

```markdown
## Output Discipline
- Every sentence load-bearing — no filler, no hedging, no caveats
- Code: deliver the diff or block, nothing else
- Errors: what failed → why → fix. Three lines.
- Done: state what changed and what to verify. Two lines.
- Never: "I hope this helps", "Feel free to ask", "Happy to help"
```

With:

```markdown
## Output Discipline
Output format and length rules are defined per-tier in economy.md.
```

- [ ] **Step 2: Verify remaining sections are intact**

```bash
grep -c "Execution Workflow\|Anti-Pattern Detection\|Error Recovery\|Scope Discipline\|Context Carry-Forward\|Session Handoff" configs/universal/supercharger.md
```

Expected: `6` (all six sections still present).

- [ ] **Step 3: Commit**

```bash
git add configs/universal/supercharger.md
git commit -m "refactor: move output discipline rules to economy.md"
```

---

### Task 8: Integrate Economy Into Installer

**Files:**
- Modify: `install.sh:9` (add source)
- Modify: `install.sh:22-23` (update usage)
- Modify: `install.sh:39-48` (add --economy arg)
- Modify: `install.sh:93-99` (add economy step)
- Modify: `install.sh:180-193` (add economy deployment)
- Modify: `install.sh:230-243` (update summary)

- [ ] **Step 1: Add economy.sh source to install.sh**

After line 14 (`source "$SCRIPT_DIR/lib/mcp.sh"`), add:

```bash
source "$SCRIPT_DIR/lib/economy.sh"
```

- [ ] **Step 2: Add --economy argument parsing**

Add `ARG_ECONOMY=""` after `ARG_SETTINGS=""` (line 20).

Add to the argument parser case block (after the `--settings` case):

```bash
    --economy)  ARG_ECONOMY="$2"; shift 2 ;;
```

Add to show_usage output:

```
  echo "  --economy TIER     Economy tier: standard, lean, minimal (default: lean)"
```

- [ ] **Step 3: Add economy selection step after role selection**

After the role selection block (after line 99, `HAS_DEVELOPER` check), add the economy step:

```bash
# Step: Economy tier
if [ -n "$ARG_ECONOMY" ]; then
  SELECTED_TIER=$(echo "$ARG_ECONOMY" | tr '[:upper:]' '[:lower:]')
  ROLES_CSV=$(IFS=,; echo "${SELECTED_ROLES[*]}")
  SELECTED_TIER=$(validate_tier_for_roles "$SELECTED_TIER" "$ROLES_CSV")
else
  echo -e "${BOLD}Select Token Economy:${NC}"
  ROLES_CSV=$(IFS=,; echo "${SELECTED_ROLES[*]}")
  select_economy_tier "$ROLES_CSV"
fi
```

- [ ] **Step 4: Add economy deployment after role deployment**

After `deploy_roles "$SCRIPT_DIR"` (line 189), add:

```bash
# Deploy economy (universal rules + active tier)
deploy_economy "$SCRIPT_DIR" "$SELECTED_TIER"
```

(The `deploy_economy` function in `lib/economy.sh` handles copying the template, injecting the active tier, and copying all tier files to `supercharger/economy/`. Call it once, after roles are deployed.)

- [ ] **Step 5: Update the install summary to show economy tier**

After the `Roles:` line in the summary, add:

```bash
  echo -e "  Economy: ${BOLD}$(capitalize "$SELECTED_TIER")${NC}"
```

- [ ] **Step 6: Update step numbering**

The installer currently says "Step 1 of 4", "Step 2 of 4", etc. Since we're adding an economy step, update the numbering. The economy step fits between roles (Step 2) and config handling (Step 3), making the new count "Step X of 5". Update all `Step N of 4` references to `Step N of 5`, and number the economy step appropriately.

- [ ] **Step 7: Update the non-interactive example in usage**

```
  echo "  ./install.sh --mode standard --roles developer --economy lean --config deploy --settings deploy"
```

- [ ] **Step 8: Run existing install tests to verify nothing is broken**

```bash
bash tests/test-install.sh
```

Expected: All existing tests pass. (Non-interactive installs will use the `--economy` flag or default to lean.)

- [ ] **Step 9: Commit**

```bash
git add install.sh
git commit -m "feat: integrate economy tier selection into installer"
```

---

### Task 9: Update Uninstaller

**Files:**
- Modify: `uninstall.sh:110`

- [ ] **Step 1: Add economy.md to the list of rule files to remove**

Replace line 110:

```bash
for f in supercharger.md guardrails.md developer.md writer.md student.md data.md pm.md anti-patterns.yml; do
```

With:

```bash
for f in supercharger.md guardrails.md economy.md developer.md writer.md student.md data.md pm.md anti-patterns.yml; do
```

The `rm -rf "$HOME/.claude/supercharger"` on line 122 already handles removing `supercharger/economy/` since it's inside the supercharger directory.

- [ ] **Step 2: Commit**

```bash
git add uninstall.sh
git commit -m "fix: add economy.md to uninstaller cleanup list"
```

---

### Task 10: Write Integration Tests

**Files:**
- Modify: `tests/test-economy.sh` (append integration tests)

- [ ] **Step 1: Add economy deployment tests to test-economy.sh**

Append to `tests/test-economy.sh` (before the `report` call):

```bash
# --- Test: economy.md deployed with active tier ---
begin_test "economy: deploy_economy creates economy.md with active tier"
setup_test_home
mkdir -p "$HOME/.claude/rules"
mkdir -p "$HOME/.claude/supercharger/economy"

SELECTED_TIER="lean"
deploy_economy "$REPO_DIR" "$SELECTED_TIER"

assert_file_exists "$HOME/.claude/rules/economy.md" &&
assert_file_contains "$HOME/.claude/rules/economy.md" "Active Tier: Lean" &&
assert_file_contains "$HOME/.claude/rules/economy.md" "Universal Output Rules" &&
assert_file_not_contains "$HOME/.claude/rules/economy.md" "{{ACTIVE_TIER}}" &&
pass
teardown_test_home

# --- Test: all tier templates deployed to supercharger/economy/ ---
begin_test "economy: all 3 tier templates in supercharger/economy/"
setup_test_home
mkdir -p "$HOME/.claude/rules"
mkdir -p "$HOME/.claude/supercharger/economy"

deploy_economy "$REPO_DIR" "lean"

assert_file_exists "$HOME/.claude/supercharger/economy/standard.md" &&
assert_file_exists "$HOME/.claude/supercharger/economy/lean.md" &&
assert_file_exists "$HOME/.claude/supercharger/economy/minimal.md" &&
pass
teardown_test_home

# --- Test: standard tier content is correct ---
begin_test "economy: standard tier has correct content"
setup_test_home
mkdir -p "$HOME/.claude/rules"
mkdir -p "$HOME/.claude/supercharger/economy"

deploy_economy "$REPO_DIR" "standard"

assert_file_contains "$HOME/.claude/rules/economy.md" "Active Tier: Standard" &&
assert_file_contains "$HOME/.claude/rules/economy.md" "Clear paragraphs, max 3 per response" &&
pass
teardown_test_home

# --- Test: minimal tier content is correct ---
begin_test "economy: minimal tier has correct content"
setup_test_home
mkdir -p "$HOME/.claude/rules"
mkdir -p "$HOME/.claude/supercharger/economy"

deploy_economy "$REPO_DIR" "minimal"

assert_file_contains "$HOME/.claude/rules/economy.md" "Active Tier: Minimal" &&
assert_file_contains "$HOME/.claude/rules/economy.md" "Telegraphic" &&
pass
teardown_test_home

# --- Test: tier validation — student blocks minimal ---
begin_test "economy: student role blocks minimal → corrects to lean"
setup_test_home

RESULT=$(validate_tier_for_roles "minimal" "student" 2>/dev/null)
if [[ "$RESULT" == "lean" ]]; then
  pass
else
  fail "expected 'lean', got '$RESULT'"
fi
teardown_test_home

# --- Test: tier validation — developer allows minimal ---
begin_test "economy: developer role allows minimal"
setup_test_home

RESULT=$(validate_tier_for_roles "minimal" "developer" 2>/dev/null)
if [[ "$RESULT" == "minimal" ]]; then
  pass
else
  fail "expected 'minimal', got '$RESULT'"
fi
teardown_test_home

# --- Test: tier validation — writer blocks minimal, allows lean ---
begin_test "economy: writer allows lean (no ceiling)"
setup_test_home

RESULT=$(validate_tier_for_roles "lean" "writer" 2>/dev/null)
if [[ "$RESULT" == "lean" ]]; then
  pass
else
  fail "expected 'lean', got '$RESULT'"
fi
teardown_test_home

# --- Test: multi-role floor — developer+student → standard floor ---
begin_test "economy: developer+student multi-role → minimal blocked"
setup_test_home

RESULT=$(validate_tier_for_roles "minimal" "developer,student" 2>/dev/null)
if [[ "$RESULT" == "lean" ]]; then
  pass
else
  fail "expected 'lean', got '$RESULT'"
fi
teardown_test_home

# --- Test: get_default_tier_for_roles ---
begin_test "economy: default tier for developer is lean"
RESULT=$(get_default_tier_for_roles "developer")
if [[ "$RESULT" == "lean" ]]; then
  pass
else
  fail "expected 'lean', got '$RESULT'"
fi

begin_test "economy: default tier for student is standard"
RESULT=$(get_default_tier_for_roles "student")
if [[ "$RESULT" == "standard" ]]; then
  pass
else
  fail "expected 'standard', got '$RESULT'"
fi

begin_test "economy: default tier for developer,student is standard (most restrictive)"
RESULT=$(get_default_tier_for_roles "developer,student")
if [[ "$RESULT" == "standard" ]]; then
  pass
else
  fail "expected 'standard', got '$RESULT'"
fi

# --- Test: full install includes economy.md ---
begin_test "economy: full non-interactive install deploys economy.md"
setup_test_home

bash "$REPO_DIR/install.sh" --mode standard --roles developer --economy lean --config deploy --settings deploy >/dev/null 2>&1

assert_file_exists "$HOME/.claude/rules/economy.md" &&
assert_file_contains "$HOME/.claude/rules/economy.md" "Active Tier: Lean" &&
assert_file_exists "$HOME/.claude/supercharger/economy/standard.md" &&
assert_file_exists "$HOME/.claude/supercharger/economy/lean.md" &&
assert_file_exists "$HOME/.claude/supercharger/economy/minimal.md" &&
pass
teardown_test_home

# --- Test: install with student + minimal → auto-corrects ---
begin_test "economy: install student+minimal auto-corrects to lean"
setup_test_home

bash "$REPO_DIR/install.sh" --mode safe --roles student --economy minimal --config deploy --settings deploy >/dev/null 2>&1

assert_file_exists "$HOME/.claude/rules/economy.md" &&
assert_file_contains "$HOME/.claude/rules/economy.md" "Active Tier: Lean" &&
pass
teardown_test_home
```

- [ ] **Step 2: Run the full test suite**

```bash
bash tests/test-economy.sh
```

Expected: All tests pass (role metadata + deployment + validation + integration).

- [ ] **Step 3: Run the full test suite to check for regressions**

```bash
bash tests/run.sh
```

Expected: All tests pass (existing + new economy tests).

- [ ] **Step 4: Commit**

```bash
git add tests/test-economy.sh
git commit -m "test: add comprehensive economy tier tests (deployment, validation, integration)"
```

---

### Task 11: Update Existing Install Tests

**Files:**
- Modify: `tests/test-install.sh`

- [ ] **Step 1: Update non-interactive install tests to include --economy flag**

In `tests/test-install.sh`, update all `install.sh` invocations that use `--config deploy --settings deploy` to also include `--economy lean`:

Line 9:
```bash
bash "$REPO_DIR/install.sh" --mode standard --roles developer --economy lean --config deploy --settings deploy >/dev/null 2>&1
```

Line 29:
```bash
bash "$REPO_DIR/install.sh" --mode safe --roles writer --economy standard --config merge --settings deploy >/dev/null 2>&1
```

Line 41:
```bash
bash "$REPO_DIR/install.sh" --mode safe --roles developer --economy lean --config skip --settings skip >/dev/null 2>&1
```

Lines 56-57 (idempotent test):
```bash
bash "$REPO_DIR/install.sh" --mode standard --roles developer --economy lean --config deploy --settings deploy >/dev/null 2>&1
bash "$REPO_DIR/install.sh" --mode standard --roles developer --economy lean --config deploy --settings deploy >/dev/null 2>&1
```

- [ ] **Step 2: Add economy.md existence check to the fresh install test**

After `assert_file_exists "$HOME/.claude/settings.json" &&` on line 18, add:

```bash
assert_file_exists "$HOME/.claude/rules/economy.md" &&
```

- [ ] **Step 3: Run install tests**

```bash
bash tests/test-install.sh
```

Expected: All tests pass.

- [ ] **Step 4: Run full test suite**

```bash
bash tests/run.sh
```

Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add tests/test-install.sh
git commit -m "test: update install tests to include economy tier flag"
```

---

### Task 12: Update CHANGELOG

**Files:**
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Read current CHANGELOG**

```bash
head -30 CHANGELOG.md
```

- [ ] **Step 2: Add v1.1.0 entry at the top (after the title)**

Add below the title/header:

```markdown
## v1.1.0 — Token Economy v2

### Added
- **Tiered token economy**: Standard (~30%), Lean (~45%), Minimal (~60%) reduction tiers
- **5 output types**: Code, Commands, Explanation, Diagnosis, Coordination — each with per-tier rules
- **Role-aware constraints**: Student floors at Standard, Writer floors at Standard, Student ceiling at Lean
- **Mid-conversation switching**: "eco standard", "eco lean", "eco minimal" keywords
- **Economy selection at install**: New installer step after role selection
- **Post-install switching**: `bash tools/economy-switch.sh [tier]` CLI tool
- **Universal output rules**: 7 always-on rules (no ceremony, no restating, lead with deliverable)
- New file: `configs/universal/economy.md` — single source of truth for token economy
- New file: `lib/economy.sh` — tier selection, validation, deployment logic
- New file: `tools/economy-switch.sh` — CLI for changing tiers after install
- New files: `configs/economy/standard.md`, `lean.md`, `minimal.md` — tier templates
- 16 new tests covering tier deployment, validation, constraint enforcement, and integration

### Changed
- Role configs now declare economy metadata (2 lines) instead of role-specific token rules
- CLAUDE.md template references economy.md instead of inline token rules
- supercharger.md Output Discipline section references economy.md
- Installer now has economy tier selection step (Step 3 of 5)
- Uninstaller cleans up economy.md

### Removed
- Inline Token Economy section from CLAUDE.md template
- Per-role Token Efficiency bullet lists (replaced with economy metadata)
- Redundant anti-pattern bullets (ceremony, repeating — now in economy.md universal rules)
- Output Discipline rules from supercharger.md (moved to economy.md)
```

- [ ] **Step 3: Commit**

```bash
git add CHANGELOG.md
git commit -m "docs: add v1.1.0 changelog for token economy v2"
```

---

### Task 13: Final Verification

- [ ] **Step 1: Run the full test suite**

```bash
bash tests/run.sh
```

Expected: All tests pass (existing + new).

- [ ] **Step 2: Test a fresh non-interactive install end-to-end**

```bash
TEST_HOME=$(mktemp -d) && HOME="$TEST_HOME" bash install.sh --mode standard --roles developer,student --economy lean --config deploy --settings deploy && echo "--- economy.md ---" && cat "$TEST_HOME/.claude/rules/economy.md" && echo "--- developer.md Token Efficiency ---" && grep -A2 "Token Efficiency" "$TEST_HOME/.claude/rules/developer.md" && echo "--- student.md Token Efficiency ---" && grep -A2 "Token Efficiency" "$TEST_HOME/.claude/rules/student.md" && rm -rf "$TEST_HOME"
```

Expected:
- economy.md contains "Active Tier: Lean" (not Standard, because developer+student defaults to standard but we explicitly chose lean, and lean is within student's range)
- developer.md has `Default economy: Lean` / `Economy range: unrestricted`
- student.md has `Default economy: Standard` / `Economy range: Standard–Lean`

- [ ] **Step 3: Test constraint enforcement**

```bash
TEST_HOME=$(mktemp -d) && HOME="$TEST_HOME" bash install.sh --mode safe --roles student --economy minimal --config deploy --settings deploy 2>&1 | grep -i "floor\|setting\|corrects" && cat "$TEST_HOME/.claude/rules/economy.md" | grep "Active Tier" && rm -rf "$TEST_HOME"
```

Expected: Warning about floor correction, economy.md shows "Active Tier: Lean".

- [ ] **Step 4: Verify economy-switch.sh works**

```bash
TEST_HOME=$(mktemp -d) && HOME="$TEST_HOME" bash install.sh --mode safe --roles developer --economy lean --config deploy --settings deploy >/dev/null 2>&1 && HOME="$TEST_HOME" bash tools/economy-switch.sh standard && grep "Active Tier" "$TEST_HOME/.claude/rules/economy.md" && rm -rf "$TEST_HOME"
```

Expected: "Active Tier: Standard" after switch.
