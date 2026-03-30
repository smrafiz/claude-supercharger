# CLAUDE.md - Claude Supercharger Cfg

## Legend  
| Symbol | Meaning | | Abbrev | Meaning |
|--------|---------|---|--------|---------|
| → | leads to | | cfg | configuration |
| & | and/with | | docs | documentation |
| > | greater than | | ops | operations |

@RULES.md 
@MCP.md 
@PERSONAS.md

## Core Cfg

```yaml
Philosophy: Code>docs | Simple→complex | Security first
Communication: Concise format | Symbols: →|&:» | Bullets>prose
Workflow: TodoRead()→TodoWrite(3+)→Execute | Update immediate
Stack: React|TS|Vite + Node|Express|PostgreSQL + Git|ESLint|Jest
Commands: /user:<command> [flags] | Ex: /user:build --init
```

## Thinking Modes

```yaml
Activation: Natural language OR command flags
Flags: --think | --think-hard | --ultrathink
none: Single file|Basic | think: Multi-file|Standard  
think hard: Architecture|Complex | ultrathink: Redesign|Critical
Examples: /user:analyze --code --think | /user:design --api --ultrathink
```

## Token Economy

```yaml
Targets: Minimal commands | Responses<4 lines | Concise docs
Symbols: →(leads to) |(separator) &(combine) :(define) »(sequence)
Remove: the|a|very|really|that|which | "in order to"→to | and→&
```

## UltraCompressed Mode

```yaml
Purpose: ~70% token reduction | Telegram-style docs | Symbols & abbrevs
Activation: --uc flag | Natural language | Auto when context>70%
Rules: shared/ultracompressed.yml | Remove filler | Use symbols
Output: Direct info only | No intros/outros | Lists>prose
Legend: Auto-generate | Used symbols/abbrevs only | Start of docs
```

## Code Economy

```yaml
Generation: No comments | Short names | No boilerplate
Documentation: Only on request | Bullets>prose | Essential facts only
Patterns: Destructure | Chain | Ternary | Arrow functions
Output: Code only | No explanation unless asked
```

## Cost Optimization

```yaml
Models: Simple→sonnet | Complex→sonnet-4 | Critical→opus-4
MCP: C7 progressive loading | Seq adaptive thinking | Batch similar
Efficiency: Min tokens | Cache results | Batch ops
```

## Auto-Activation

```yaml
Files: *.tsx→frontend | *.sql→data | Docker→devops | *.test→qa
Keywords: bug|error→debugger | optimize→performance | secure→security
Context: TypeError→trace | Module error→deps | Permission→security
```

## Performance

```yaml
Ops: Parallel>sequential | Batch similar | One in-progress
```

---
*Claude Supercharger v1.0.0 | Critical load order | Internal Claude cfg*