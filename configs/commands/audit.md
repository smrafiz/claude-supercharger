Sweep $ARGUMENTS for inconsistencies. Read the relevant files first, then check each dimension.

**Dimensions:**

1. **Naming** — Are conventions applied consistently? Check: camelCase vs snake_case, plural vs singular, verb-noun patterns, abbreviations. Flag when the same concept is named differently in different places.

2. **Patterns** — Is the same problem solved different ways in different places? Check: error handling style, async patterns, state management, data fetching, logging.

3. **Documentation** — Do comments, README, and inline docs match what the code actually does? Flag outdated docs, missing docs for public interfaces, and misleading comments.

4. **Interfaces** — Are API contracts, function signatures, or types inconsistent with their actual usage? Flag mismatches between what a function promises and what callers expect.

5. **Structure** — Do similar modules follow the same layout? Check: file organization, export patterns, test file placement.

Output format:
```
## INCONSISTENCIES FOUND

[dimension]
- [file:line] vs [file:line] — [what conflicts] — established pattern: [which is correct based on majority usage]

## PATTERN RECOMMENDATIONS
- [what the consistent pattern should be, with example]

## CLEAN — no issues found in:
- [dimension]: consistent throughout
```

Read-only. Flag only — do not fix. Skip dimensions with no findings.
