# Changelog

All notable changes to Claude Supercharger will be documented in this file.

## [1.0.0] - 2026-03-30

### Added - Prompt Master Integration

**8 Novel Techniques:**

1. **35 Anti-Pattern Library** [H:8]
   - Comprehensive credit-killing pattern detection across 6 categories
   - Task, Context, Format, Scope, Reasoning, Agentic patterns
   - Auto-fix silently or flag if changes intent

2. **Pre-Delivery Verification** [H:8]
   - 6-point quality checklist before claiming "done"
   - Target ID, constraints preserved, signal words, fabrication check, token efficiency, binary success

3. **Forbidden Techniques Blacklist** [C:10]
   - Prevents fabrication-prone methods
   - Mixture of Experts, Tree of Thought, Graph of Thought, Universal Self-Consistency
   - Chain of Thought restrictions on reasoning models (o3/o4/R1/DeepSeek)

4. **Output Lock Discipline** [H:8]
   - Reduces ceremonial text by ~40%
   - Final deliverables: Code/solution + 1 optimization sentence
   - Exempts TodoWrite, tool descriptions, error recovery

5. **Intent Extraction Framework** [H:7]
   - 9-dimension analysis for complex requests
   - CRITICAL: Task, Target tool, Output format
   - CONDITIONAL: Constraints, Input, Context, Audience, Success criteria, Examples

6. **Memory Block Template** [M:6]
   - Formal pattern for context carry-forward
   - Stack & tool decisions, architecture choices, constraints, failures
   - Multi-turn task support

7. **Tool-Specific Optimization** [M:6]
   - Per-model constraints for 10+ AI models
   - Claude Opus 4.x, o3/o4-mini, GPT-5.x, Gemini, DeepSeek-R1, Qwen variants, Ollama

8. **Success Criteria Extraction** [H:7]
   - Converts vague goals to binary pass/fail
   - "make it better" → "Done when: passes tests + handles null"

### Installation & Migration

- **Smart Merge Script** [M:6]
  - Detects existing configurations
  - Preserves custom rules, personas, MCP configs
  - Appends Supercharger enhancements without replacing
  - Interactive installation with fresh/merge/cancel options

- **Migration Guide** [M:5]
  - Comprehensive conflict resolution strategies
  - Cherry-picking individual features
  - Manual merge steps with examples
  - Persona merging, rule deduplication, MCP integration
  - Troubleshooting and backup restoration

- **MCP Server Setup** [M:6]
  - Interactive installation script (mcp-setup.sh)
  - 12 recommended servers across 3 tiers
  - API key management and validation
  - Preserves existing MCP configurations
  - Tier 1 (Context7, Sequential, Memory), Tier 2 (GitHub, Brave, Filesystem), Tier 3 (Playwright, Puppeteer, Prisma, Neon, Magic UI, Slack)
  - Complete setup guide (docs/MCP_SETUP.md) with API key instructions, manual config, troubleshooting

### Enhanced

- **Execution Priority** [H:8]: 8-step workflow for complex requests
- **Ambiguity Resolution & Intent Extraction** [H:7]: Merged into single unified system
- **Session Awareness** [H:9]: Memory Block as explicit template
- **Verification Gate** [H:8]: Enhanced with Pre-Delivery checks

### Changed

- Initial release of Claude Supercharger v1.0.0
- All core files updated with Prompt Master patterns
- Comprehensive anti-patterns reference file added

---

## [4.0.0] - 2025-XX-XX

### Initial Release

- Core protocols (Critical Thinking, Evidence-Based, Thinking Modes)
- Severity system (CRITICAL, HIGH, MEDIUM, LOW)
- Ops standards (Files, Tasks, Tools, Performance, Git, Communication)
- Dev practices (KISS, YAGNI, SOLID, DRY, Clean Code, Testing, Performance)
- 9 Cognitive personas (architect, frontend, backend, analyzer, security, mentor, refactorer, performance, qa)
- MCP orchestration (Context7, Sequential, Magic, Puppeteer)
- Session awareness and error recovery
- Smart defaults and handling
- Security standards and sandboxing
- Ambiguity resolution
- Project quality management
