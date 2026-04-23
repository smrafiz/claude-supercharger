Run a multi-lens review by dispatching parallel specialist agents: $ARGUMENTS

Fan out the same target to three independent reviewers, then synthesize. Each agent sees the same code but looks through a different lens — findings that appear in multiple lenses are highest priority.

**Step 1 — Identify target**

If $ARGUMENTS is empty, review the current branch diff (`git diff main...HEAD`).
If $ARGUMENTS is a file path, PR number, or description — use that.

**Step 2 — Dispatch three agents in parallel**

Spawn these three agents simultaneously using the Agent tool:

**Agent 1 — Security Reviewer**
> Read the target. Find: injection vulnerabilities, auth/authz gaps, credential exposure, XSS, CSRF, insecure defaults, dangerous shell patterns, hardcoded secrets, missing input validation. Produce: MUST FIX / SHOULD FIX findings with file:line evidence. Security issues only — ignore style and performance.

**Agent 2 — Performance Reviewer**
> Read the target. Find: N+1 queries, missing indexes, unnecessary re-renders, blocking I/O in hot paths, large bundle additions, memory leaks, expensive operations in loops, missing caching opportunities. Produce: MUST FIX / SHOULD FIX findings with file:line evidence. Performance issues only — ignore security and style.

**Agent 3 — DX / Correctness Reviewer**
> Read the target. Find: logic bugs, incorrect error handling, missing edge cases, poor variable naming, violated conventions, dead code, missing tests for critical paths, API misuse. Produce: MUST FIX / SHOULD FIX findings with file:line evidence. Correctness and developer experience only — ignore security and performance.

**Step 3 — Synthesize**

After all three agents complete:

1. Collect all MUST FIX findings across agents
2. Flag any finding that appears in 2+ lenses (cross-lens = highest confidence)
3. Present a unified report:

```
## Multi-Lens Review: [target]

### Cross-Lens Findings (highest confidence)
[findings flagged by 2+ agents]

### Security
[agent 1 findings]

### Performance
[agent 2 findings]

### DX / Correctness
[agent 3 findings]

### Summary
- Total MUST FIX: N
- Total SHOULD FIX: N
- Cross-lens: N
```
