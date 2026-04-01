# Token Economy v2 — Design Spec

**Date:** 2026-04-01
**Supersedes:** 2026-04-01-token-economy-design.md (v1)
**Goal:** Tiered token economy with user-selectable verbosity, role-aware constraints, and per-output-type calibration
**Scope:** New economy.md, modified CLAUDE.md, supercharger.md, 5 role configs, installer, new CLI tool

## Motivation

The v1 token economy shipped flat rules — "1-3 lines simple, max 10 lines complex" — applied uniformly. This creates two problems:

1. **Blunt calibration.** A single line-count target governs code, explanations, errors, and planning equally. A Student explanation and a Developer error fix need fundamentally different output budgets.
2. **No user control.** Some users want telegraphic output; others want concise but readable prose. The v1 system offers no choice.

v2 introduces three named tiers (Standard, Lean, Minimal), five output types, and role-aware floor/ceiling constraints — selectable at install time and switchable mid-conversation.

## Design

### 1. Universal Output Rules

These apply at every tier and cannot be overridden:

1. Lead with the deliverable — code, answer, or action. Not the reasoning.
2. Never restate the user's request or summarize what you just did.
3. No ceremony: skip "Here's what I found", "Let me explain", "I'll now...", "Happy to help".
4. One completion per turn — no unsolicited alternatives.
5. If the answer is yes or no, say that. Not a paragraph.
6. Lists over prose. Tables over lists. Bare output over wrapped output.
7. Clarifying questions: max 3, one per message when possible.

### 2. Output Types

All responses fall into one of these types. Tier modifiers set expectations per type.

- **Code** — generated code blocks, diffs, implementations, file contents
- **Commands** — shell commands, git operations, tool invocations
- **Explanation** — teaching, reasoning, "why", architecture discussion
- **Diagnosis** — errors, status, what happened, what to do next
- **Coordination** — planning, clarifying questions, scope negotiation, handoff summaries

Classification rules:
- If a response mixes types (e.g., code + explanation), each section follows its own type's rules
- When in doubt, treat it as the shorter type — Code over Explanation, Diagnosis over Coordination

### 3. Economy Tiers

#### Standard (~30% reduction)
Concise, natural English. Complete sentences. No filler, but readable.

- **Code**: Full implementation with filename context. No inline comments.
- **Commands**: Command with one-line purpose if non-obvious.
- **Explanation**: Clear paragraphs, max 3 per response. Analogies welcome.
- **Diagnosis**: What failed, why, fix — up to 5 lines.
- **Coordination**: Full sentences, structured with bullets. Max 8 lines.

#### Lean (~45% reduction)
Every word load-bearing. Fragments OK. Deliver, don't narrate.

- **Code**: Diff or block only. Filename as header, no surrounding text.
- **Commands**: Bare command. No wrapper, no "I'll run...".
- **Explanation**: Bullets only. One concept per bullet. Max 8 bullets.
- **Diagnosis**: What → why → fix. Three lines max.
- **Coordination**: Bullets, no prose. Max 5 lines.

#### Minimal (~60% reduction)
Telegraphic. Bare deliverables. Context only when ambiguity is dangerous.

- **Code**: Block only. No filename unless multiple files in response.
- **Commands**: Command only. Zero surrounding text.
- **Explanation**: Shortest accurate form. Fragments, abbreviations OK. Max 4 bullets.
- **Diagnosis**: One-line: [what failed] → [fix]. Two lines if cause is non-obvious.
- **Coordination**: Terse fragments. Max 3 lines.

### 4. Role Defaults & Constraints

Each role has a default tier and an allowed range. If a user selects a tier outside a role's range, the system corrects to the nearest allowed tier with a one-line notice.

| Role          | Default  | Floor    | Ceiling  |
|---------------|----------|----------|----------|
| Developer     | Lean     | —        | —        |
| Student       | Standard | Standard | Lean     |
| Writer        | Standard | Standard | —        |
| Data Analyst  | Lean     | —        | —        |
| PM            | Lean     | —        | —        |

#### Multi-role behavior
When multiple roles are active, the most restrictive floor wins.
Example: Developer + Student active → floor is Standard (from Student).

#### Role file format
Each role file gets two lines appended to its Token Efficiency section:

```
Default economy: [tier]
Economy range: [floor]–[ceiling]
```

Roles with no restrictions:

```
Default economy: [tier]
Economy range: unrestricted
```

### 5. Mid-Conversation Switching

Keyword triggers:

```
"eco standard" → switch to Standard tier
"eco lean"     → switch to Lean tier
"eco minimal"  → switch to Minimal tier
```

Behavior:
- Takes effect immediately for the next response
- Respects role floor/ceiling — if blocked, one-line notice with correction
- Persists for the rest of the conversation (not permanent)
- Can combine with role switch: "as student eco standard"

### 6. Installation Integration

#### Installer step (after role selection):

```
Select token economy tier:
  1) Standard  — concise, natural English (~30% reduction)
  2) Lean      — every word earns its place (~45% reduction) [default]
  3) Minimal   — telegraphic, bare output (~60% reduction)
```

- Default: Lean (if user skips or presses Enter)
- If selected tier conflicts with role floor/ceiling: display notice, auto-correct to nearest allowed tier
- Writes active tier to economy.md during deployment

#### Post-install switching:

```bash
bash tools/economy-switch.sh [standard|lean|minimal]
```

- Rewrites the active tier block in ~/.claude/rules/economy.md
- Validates against active roles' floor/ceiling
- Takes effect on next Claude Code session

### 7. File Deployment

Install deploys:
- `~/.claude/rules/economy.md` — universal rules + active tier definition
- `~/.claude/supercharger/economy/standard.md` — Standard tier block
- `~/.claude/supercharger/economy/lean.md` — Lean tier block
- `~/.claude/supercharger/economy/minimal.md` — Minimal tier block

Each tier file contains only its tier definition (name, description, 5 output-type rules). The `economy-switch.sh` tool reads the selected tier file and writes its content into the active tier section of `~/.claude/rules/economy.md`.

Role files updated with two metadata lines during role deployment.

## Migration from v1

### Files modified:

1. **configs/universal/CLAUDE.md**
   - Remove "Token Economy" section (7 lines)
   - Remove redundant ceremony bullets from "Anti-Patterns to Avoid"
   - Add one-line reference: "Token economy rules loaded from economy.md"

2. **configs/universal/supercharger.md**
   - Remove "Output Discipline" section — absorbed into universal rules in economy.md
   - Keep "Execution Workflow", "Error Recovery", "Scope Discipline" untouched

3. **configs/roles/developer.md**
   - Replace "Token Efficiency" section with:
     ```
     ## Token Efficiency
     Default economy: Lean
     Economy range: unrestricted
     ```

4. **configs/roles/student.md**
   - Replace "Token Efficiency" section with:
     ```
     ## Token Efficiency
     Default economy: Standard
     Economy range: Standard–Lean
     ```

5. **configs/roles/writer.md**
   - Replace "Token Efficiency" section with:
     ```
     ## Token Efficiency
     Default economy: Standard
     Economy range: Standard–unrestricted
     ```

6. **configs/roles/data.md**
   - Replace "Token Efficiency" section with:
     ```
     ## Token Efficiency
     Default economy: Lean
     Economy range: unrestricted
     ```

7. **configs/roles/pm.md**
   - Replace "Token Efficiency" section with:
     ```
     ## Token Efficiency
     Default economy: Lean
     Economy range: unrestricted
     ```

### New files:

8. **configs/universal/economy.md** — universal rules + all 3 tier definitions + active tier marker + switching keywords
9. **tools/economy-switch.sh** — CLI tool to swap active tier post-install
10. **lib/economy.sh** — installer functions: tier selection, validation, deployment

### Preserved (no changes):

- Verification Gate, Safety Boundaries, Context Management (CLAUDE.md)
- Execution Workflow, Error Recovery, Scope Discipline, Clarification Mode, Session Handoff (supercharger.md)
- Role behavior sections: teaching approach, code output, analysis standards, writing process, planning
- guardrails.md, anti-patterns.yml
- All existing hooks

## Success Criteria

- [ ] economy.md deployed with universal rules and active tier
- [ ] All 3 tiers produce measurably different output behavior
- [ ] Role floor/ceiling constraints enforced at install and mid-conversation
- [ ] Mid-conversation switching works via "eco [tier]" keywords
- [ ] economy-switch.sh validates against active roles
- [ ] Installer prompts for tier selection after role selection
- [ ] Student + Minimal auto-corrects to Lean with notice
- [ ] Multi-role floor resolution works (most restrictive wins)
- [ ] No duplication between economy.md and role files
- [ ] All existing tests pass
- [ ] New tests cover tier selection, switching, and constraint validation
- [ ] CHANGELOG updated
