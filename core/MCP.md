# MCP.md - Model Context Protocol Ops

## Legend
| Symbol | Meaning | | Abbrev | Meaning |
|--------|---------|---|--------|---------|
| → | leads to | | ops | operations |
| & | and/with | | UI | user interface |
| w/ | with | | impl | implementation |

## Decision Matrix

```yaml
Flag Control:
  --c7: Force Context7→docs | --seq: Force Sequential→analysis | --magic: Force Magic→UI
  --pup: Force Puppeteer→browser | --all-mcp: Enable all | --no-mcp: Disable all

User Triggers (no flags):
  "docs for X" → C7(resolve-library-id: X) → get-docs
  "how to use Y in Z" → C7(resolve-library-id: Z) → get-docs(topic: Y)
  "need button/form/component" → Magic(builder) → integrate
  "why slow/broken" → Sequential(analysis) → impl fix
  "design architecture" → Sequential(system design) → C7(patterns)
  
Context Triggers (flags override):
  Import errors → C7(resolve-library-id) → verify docs
  Complex debugging → Sequential(root cause) → native impl  
  UI requests → Magic(builder/refiner) → Puppeteer(test)
  Perf issues → Sequential(analysis) → optimize impl

Research-First (shared/research-first.yml):
  External lib detected → C7 lookup REQUIRED (blocks w/o docs)
  New component → Magic search REQUIRED or existing pattern
  API integration → WebSearch REQUIRED for official docs
  Unknown pattern → Sequential thinking + research REQUIRED
  Confidence < 90% → Impl BLOCKED until research complete
  
Task Complexity:
  Simple queries → Native tools only (unless flagged)
  Lib questions → C7 progressive loading (or --c7)
  Multi-step problems → Sequential adaptive thinking (or --seq)
  UI generation → Magic + integration (or --magic)
  Full workflows → Multi-MCP orchestration (or --all-mcp)
```

## Execution Playbooks

```yaml
Lib Research: C7 resolve-library-id w/ user term → options if multiple → C7 get-docs w/ topic → Sequential if insufficient → impl
Ex: "React forms?" → C7 resolve("react") → C7 get-docs(topic:"forms") → impl form code

Complex Analysis: Sequential problem decomposition → guide C7 docs lookup → combine analysis+docs→impl plan → execute w/ native
Ex: "App slow debug" → Sequential(analyze perf bottlenecks) → C7 get-docs optimization patterns → impl fixes

UI Generation: Magic builder w/ user requirements+project context → Magic refiner if needed → integrate component → Puppeteer validation
Ex: "Dashboard w/ charts" → Magic builder("dashboard","charts") → edit files integrate → Puppeteer screenshot
```

## Token Economics

```yaml
Budget: Native:0 | Light MCP:100-500 | Medium MCP:500-2K | Heavy MCP:2K-10K
Escalation: 1.Native first simple tasks 2.C7 lib questions 3.Sequential complex analysis 4.Combine MCPs synergy
Abort: >50% context→native | MCP timeout/error→fallback | Diminishing returns→stop MCP
Cost: Quick→C7 only | Architecture→Sequential | UI→Magic | Else→Native
UltraCompressed: --uc flag|High context|Token budget | ~70% reduction | Clarity→conciseness | Legend auto-gen
```

## Quality Control

```yaml
C7: ✓Relevant docs→Proceed | ⚠Partial→Try different terms | ✗No match→Sequential alternatives
Sequential: ✓Clear analysis+steps→Impl | ⚠Partial→Continue thoughts | ✗Unclear/timeout→Native+user questions
Magic: ✓Component matches→Integrate | ⚠Close needs changes→Refiner | ✗Poor→Try different terms
Multi-MCP: Results enhance each other | Conflict→Most authoritative | Redundant→Stop calls
```

## Tool-Specific Optimization [M:6]

```yaml
Per-tool constraints enhance routing & output quality:

Claude (all versions):
  - XML tags for multi-section prompts: <context>, <task>, <constraints>, <output_format>
  - Explain WHY not just WHAT (Claude generalizes better from reasoning)
  - Always specify output format and length explicitly

Claude Opus 4.x specific:
  - Over-engineers by default → add "Only make changes directly requested. Do not add features, abstractions, or refactoring beyond what was asked."
  - Prevent scope creep on agentic tasks

OpenAI o3/o4-mini (reasoning models):
  - SHORT clean instructions ONLY (these models reason across thousands of internal tokens)
  - NEVER add CoT, "think step by step", or reasoning scaffolding (actively degrades output)
  - Prefer zero-shot first, add few-shot only if strictly needed
  - Keep system prompts under 200 words (longer prompts hurt performance)

OpenAI GPT-5.x:
  - Compact structured outputs work well
  - Constrain verbosity when needed: "Respond in under 150 words. No preamble. No caveats."
  - Strong at long-context synthesis and tone adherence

Gemini 2.x/3 Pro:
  - Prone to hallucinated citations → add "Cite only sources you are certain of. If uncertain, say [uncertain]."
  - For grounded tasks add "Base your response only on the provided context. Do not extrapolate."
  - Strong at long-context and multimodal (leverage large context window)

DeepSeek-R1:
  - Reasoning-native like o3 → SHORT clean instructions, no CoT
  - Outputs reasoning in <think> tags by default → add "Output only the final answer, no reasoning." if needed

Qwen 2.5 (instruct):
  - Excellent instruction following, JSON output, structured data
  - Provide clear system prompt defining role
  - Shorter focused prompts outperform long complex ones

Qwen3 (thinking mode):
  - Two modes: thinking (/think or enable_thinking=True) and non-thinking
  - Thinking mode: treat like o3 (short, no CoT, no scaffolding)
  - Non-thinking mode: treat like Qwen2.5 (full structure, explicit format, role assignment)

Ollama (local models):
  - ALWAYS ask which model is running before writing (Llama3/Mistral/Qwen2.5/CodeLlama differ)
  - System prompt is most impactful lever
  - Shorter simpler prompts outperform complex ones (local models lose coherence with deep nesting)
  - Temperature 0.1 for coding/deterministic tasks, 0.7-0.8 for creative tasks

Integration with Context Triggers:
  - Enhance existing MCP routing with these tool-specific constraints
  - Apply automatically when tool is detected or selected
  - Override with explicit flags if user specifies different approach
```

## Persona Integration

```yaml
Persona Preferences:
  architect: Sequential(design)+C7(patterns)+avoid Magic | frontend: Magic(UI)+Puppeteer(test)+C7(React/Vue docs)
  backend: C7(API docs)+Sequential(scale analysis)+avoid Magic | analyzer: Sequential(root cause) primary+C7(solutions) secondary
  security: Sequential(threats)+C7(security patterns)+Puppeteer(test) | mentor: C7(learning)+Sequential(explanations)+avoid Magic
  refactorer: Sequential(analysis)+C7(patterns)+avoid Magic/Puppeteer | perf: Sequential(bottlenecks)+Puppeteer(metrics)+C7(optimization)
  qa: Puppeteer(testing)+Sequential(edge cases)+C7(testing frameworks)

Behaviors: architect→Long Sequential system design | frontend→Quick Magic components | analyzer→Deep Sequential before solutions
```

## Command Integration

```yaml
Planning: Default execute immediately | --plan flag→Forces planning mode | --skip-plan→Skip (redundant w/ default)
MCP Flags: --c7/--no-c7 | --seq/--no-seq | --magic/--no-magic | --pup/--no-pup | --all-mcp | --no-mcp
Auto-Activation (no flags): /user:build→Magic(UI) if frontend | /user:analyze→Sequential complex | /user:design→Sequential+C7
/user:explain→C7 if lib mentioned else native | /user:improve→Sequential→C7 | /user:scan→Native only (security)
Priority: Explicit flags>Auto-activation>Context triggers | --no-mcp overrides all | --no-[server] overrides specific
Context Share: Sequential→feeds C7 topic selection | C7 docs→inform Magic generation | Magic→tested w/ Puppeteer | All cached
Execution: Default→Execute immediately | --plan flag→Show plan before changes | User controls→Full control
```

## Failure Recovery & Best Practices

```yaml
Failures: C7: Lib not found→broader terms | Docs incomplete→Sequential | API timeout→cache partial+native
Sequential: Timeout→use partial+note limit | Token limit→summarize+native | Unclear→ask questions+avoid retry
Magic: No components→try different terms once | Poor quality→refiner w/ context | Integration issues→document+native
Multi-MCP: Conflict→most reliable source | Resource exhaustion→single best MCP | Partial failures→continue successful only

DO: Match MCP→user need | Set token budgets | Validate before impl | Cache patterns | Graceful fallback
Use C7 ALL external lib docs (research-first.yml enforced) | Cite MCP sources in impl
DON'T: MCPs for simple tasks native handles | Chain w/o validation | Exceed 50% context | Retry failed w/o change | MCPs when immediate needed
OPTIMIZE: Batch similar calls | Reuse session results | Start least expensive | Prefer native file ops | Document successful patterns
```

---
*Claude Supercharger v1.0.0 | Ops MCP instructions for Claude Code intelligence + Prompt Master integration*