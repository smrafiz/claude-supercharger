# Prompt Master Integration

Claude Supercharger v1.0.0 integrates 8 novel techniques from [Prompt Master](https://github.com/nidhinjs/prompt-master).

---

## What is Prompt Master?

A Claude skill that generates optimized prompts for 30+ AI tools (ChatGPT, Midjourney, Cursor, GitHub Copilot, Devin, etc.) by applying prompt engineering best practices automatically.

---

## Integrated Techniques

### 1. 35 Anti-Pattern Library

**Credit-killing patterns** across 6 categories:

- **Task**: Vague verbs, two tasks in one, no success criteria
- **Context**: Assumed knowledge, hallucination invites, undefined audience
- **Format**: Missing output format, implicit length, vague aesthetics
- **Scope**: No boundaries, no stop conditions, unlocked filesystem
- **Reasoning**: Missing CoT for logic, CoT on reasoning models
- **Agentic**: No start/target state, silent agents, no review triggers

**Location**: `~/.claude/shared/anti-patterns.yml`

---

### 2. Intent Extraction (9 Dimensions)

**CRITICAL** (always ask):
- Task
- Target tool
- Output format

**CONDITIONAL** (if complex):
- Constraints
- Input
- Context
- Audience
- Success criteria
- Examples

**Max 3 clarifying questions** before proceeding.

---

### 3. Forbidden Techniques Blacklist

**NEVER use** fabrication-prone techniques:
- ✗ Mixture of Experts (no real routing)
- ✗ Tree of Thought (simulated branching)
- ✗ Graph of Thought (requires external engine)
- ✗ Universal Self-Consistency (contaminated sampling)
- ✗ Chain of Thought on reasoning models (o3/o4/R1/DeepSeek degrade)

**ALLOWED techniques**:
- ✓ Role assignment
- ✓ Few-shot examples (2-5)
- ✓ XML structure
- ✓ Grounding anchors
- ✓ Chain of Thought (standard models only)

---

### 4. Tool-Specific Optimization

**Claude Opus 4.x**:
- Over-engineers by default → add "Only make changes directly requested"
- Prevent scope creep on agentic tasks

**o3/o4-mini** (reasoning models):
- SHORT clean instructions ONLY
- NEVER add CoT (degrades output)
- System prompts <200 words

**GPT-5.x**:
- Compact structured outputs
- Constrain verbosity: "Under 150 words. No preamble."

**Gemini 2.x/3 Pro**:
- Prone to hallucinated citations → "Cite only certain sources. If uncertain, say [uncertain]."
- Grounded tasks: "Base response only on provided context."

**DeepSeek-R1**:
- Reasoning-native → SHORT instructions, no CoT
- Outputs in <think> tags → "Output only final answer" if needed

**Qwen / Ollama / Local models**:
- Model-specific guidance
- Shorter simpler prompts
- Temperature recommendations

---

### 5. Pre-Delivery Verification (6-Point Checklist)

Before claiming "done":
- [ ] Target/tool correctly identified
- [ ] Critical constraints preserved (first 30% if long)
- [ ] Strongest signal words (MUST>should, NEVER>avoid)
- [ ] No fabricated techniques
- [ ] Token efficiency (every sentence load-bearing)
- [ ] Binary success criteria met

---

### 6. Output Lock Discipline

**NEVER**:
- Discuss theory unless explicitly asked
- Pad output with unrequested explanations
- Ask more than 3 clarifying questions

**Final deliverables**:
Code/solution + 1 optimization sentence + setup instructions (if needed)

**Exempt**:
- TodoWrite progress updates
- Tool operation descriptions
- Error recovery explanations

---

### 7. Memory Block Template

**Trigger**: User references prior work | Multi-turn complex tasks (3+ related prompts)

**Template**:
```
## Context (carry forward)
- Stack & tool decisions established: [list]
- Architecture choices locked: [list]
- Constraints from prior turns: [list]
- What was tried & failed: [list]
```

---

### 8. Success Criteria Extraction

Convert vague goals to binary pass/fail:

- "make it better" → "Done when: passes tests + handles null"
- "improve performance" → "Done when: load time <2s + 60fps"
- "fix the bug" → "Done when: error eliminated + tests pass"

---

## Full Prompt Master Skill (Optional)

Want the full Prompt Master skill for generating prompts for other AI tools?

1. Download: https://github.com/nidhinjs/prompt-master
2. Install via claude.ai skills interface
3. Use alongside Claude Supercharger for comprehensive prompt engineering

---

## Credits

- **Prompt Master** by [@nidhinjs](https://github.com/nidhinjs)
- 8 techniques integrated into Claude Supercharger v1.0.0
