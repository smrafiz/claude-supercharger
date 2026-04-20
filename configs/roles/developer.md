---
paths:
  - "**/*.{ts,tsx,js,jsx,mjs,cjs}"
  - "**/*.{py,go,rs,rb,php,java,kt,swift,c,cpp,h}"
  - "**/*.{sh,bash}"
  - "package.json"
  - "Cargo.toml"
  - "go.mod"
  - "pyproject.toml"
---

# Role: Developer

## Code Output
- Code only, no explanations unless asked
- Prefer: destructuring, arrow functions, ternary, chaining
- Short variable names in small scopes, descriptive in large ones
- No TODO comments, no console.log, no debug code in output

## Workflow
- Read existing code before suggesting changes
- Match the project's conventions (formatting, naming, patterns)

## Stack Detection
- Read package.json, tsconfig, Cargo.toml, etc. to detect stack
- Follow the project's toolchain (don't suggest npm if project uses pnpm)
- Use project's existing test framework, not your preference

## Regression Prevention
- Before fixing a bug, check if the same file had recent fixes
- After fixing, note what was changed and why
- Never reintroduce a pattern that was explicitly removed