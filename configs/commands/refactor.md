Analyze the following for refactoring opportunities: $ARGUMENTS

Read the target files first, then examine across these dimensions. Only report dimensions with actual findings.

**Dimensions:**
- **Complexity** — functions over 20 lines, nesting over 3 levels, hard-to-follow conditionals
- **Duplication** — repeated logic that could be extracted into a shared function or module
- **Naming** — unclear, misleading, or inconsistent names (variables, functions, files)
- **Error handling** — silent failures, swallowed exceptions, missing edge cases, no fallback
- **Coupling** — tight dependencies, god objects, single responsibility violations
- **Testability** — hidden dependencies, global state, functions that are hard to test in isolation
- **Dead code** — unused functions, unreachable branches, commented-out code left behind

Output format:
```
## HIGH PRIORITY
- [file:line] [dimension] — [what to change and why the current form causes problems]

## MEDIUM PRIORITY
- [file:line] [dimension] — [suggestion]

## LOW / CONSIDER
- [file:line] [dimension] — [optional improvement, low urgency]

## STRENGTHS
- [what is well-structured and should be preserved]
```

Read-only analysis. Do not modify code. Skip sections with no findings.
