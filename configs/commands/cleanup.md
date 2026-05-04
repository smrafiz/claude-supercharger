Dead code and unused-import removal for: $ARGUMENTS

Two-tier safety model. Auto-fix anything in **Tier 1**. Require explicit approval for **Tier 2**.

## Tier 1 — auto-fix (safe)

Apply these directly without asking:

- Unused imports (no references in file scope)
- Unused local variables (declared, never read)
- Commented-out code blocks > 3 lines old (>30 days in git blame)
- Unreachable code (after `return`, `throw`, `process.exit`, `panic`, `os.Exit`)
- Empty functions/methods that are never called and have no `@override` / interface obligation
- Duplicate consecutive imports

## Tier 2 — require approval (risky)

Surface as a list. Do not delete without user approval:

- Functions/classes/types with **zero callers in this codebase** but **exported** (could be public API)
- Symbols referenced only in tests (could be intentional test-only utilities)
- Files that appear orphaned but match conventional plugin/loader patterns (e.g., `routes/*.ts`, `migrations/*`, `*.module.ts`)
- Symbols referenced via dynamic dispatch (`getattr`, `require()` with template, reflection)

## Process

1. Scan the target ($ARGUMENTS — file, directory, or whole project)
2. Apply Tier 1 fixes; report what was removed (file:line for each)
3. Compile Tier 2 findings into a numbered list with evidence per item:
   - Symbol name
   - Where defined
   - Why flagged (zero callers / test-only / dynamic-dispatch suspect)
   - Confidence (low/med/high)
4. Run available type checks / tests after Tier 1 changes — if anything fails, halt and report
5. Wait for user approval on Tier 2 items individually (not bulk)

## Output format

```
=== Tier 1: Applied ===
- [file:line] removed unused import: [name]
- [file:line] removed unreachable code (after [return|throw])
- ...
Tests passing: [yes/no]

=== Tier 2: Awaiting approval ===
1. [symbol] @ [file:line]
   - Definition: [signature]
   - Why flagged: [reason]
   - Confidence: [low/med/high]
   - Risk if removed: [public API break / test removal / hidden dynamic call]
2. ...

Reply with the numbers you want removed (e.g., "1, 3") or "skip all".
```

If no findings, say so plainly. Do not pad with marginal items.
