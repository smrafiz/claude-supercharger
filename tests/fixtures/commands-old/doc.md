Generate documentation for: $ARGUMENTS

Read the target file first. Detect the documentation style in use from existing docs in the project (JSDoc, TypeDoc, docstrings, rustdoc, godoc, etc.). Match existing documentation patterns before inventing new ones.

**Scope — infer from $ARGUMENTS or default to `file`:**
- **function** — doc block for a single function/method
- **file** — doc blocks for all exported/public functions in the file
- **module** — high-level module overview + all public exports
- **readme** — a README section (usage, API table, examples)

**Documentation rules:**
- Public interfaces always get docs — private/internal only if complex
- Include: purpose, parameters (name + type + description), return value, thrown errors
- Add a usage example for any non-trivial function
- Do not restate what the code obviously does — explain *why* or *when* to use it
- Match the project's existing voice (terse vs verbose, formal vs casual)

**Before writing:**
1. Read the target — understand intent, not just signature
2. Scan for existing docs in the project — match format exactly
3. Note any functions that are already documented — skip or flag as needing update

**Output format:**
```
## STYLE DETECTED
[JSDoc / docstring / rustdoc / godoc / none — defaulting to X]

## DOCUMENTED
[file path]

[full file contents with documentation added, or doc blocks only if --inline not desired]

## SKIPPED
- [function:line] — [reason: private, trivial, already documented]
```

Write docs inline in the source file. Do not create separate doc files unless the scope is `readme`.
