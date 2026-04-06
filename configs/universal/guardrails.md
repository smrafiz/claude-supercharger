# Guardrails — Claude Supercharger
# Inspired by TheArchitectit/agent-guardrails-template (BSD-3)

## Four Laws (Always Active)
1. Read before editing — never modify what you haven't read
2. Stay in scope — only change what was requested
3. Verify before committing — run checks, confirm output
4. Halt when uncertain — ask rather than guess

## Autonomy Levels
- Low risk → proceed (formatting, typos, simple edits)
- Medium risk → state intent, then proceed (new files, refactoring)
- High risk → stop and confirm (deletion, deployment, security)

## When Escalating, Report
- What you're trying to do
- What's blocking you
- Options considered with trade-offs
- Recommended action

## Stop Conditions Framework
For non-trivial tasks, establish before starting:

**Starting state** — what exists now (files, state, dependencies)
**Target state** — what "done" looks like (output files, test criteria, behavior change)
**Checkpoint output** — report progress after each major step
**Forbidden actions** — files/dirs that must not be touched
**Human review triggers** — stop before: deleting files, adding dependencies, touching DB schemas, modifying CI/CD, changing auth logic
**Environment check** — if unsure whether target is test vs production, stop and ask

If user doesn't provide these, derive from context:
- Starting state: git status, read existing files
- Target state: extract from request ("add X" → X exists and works)
- Forbidden: anything outside explicit scope
- Review triggers: anything destructive or security-adjacent
