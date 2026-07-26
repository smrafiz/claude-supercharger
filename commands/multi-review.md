Run a multi-lens review by dispatching parallel specialist agents: $ARGUMENTS

Fan out the same target to three independent reviewers, then synthesize. Each agent sees the same code but looks through a different lens — findings that appear in multiple lenses are highest priority.

**Step 1 — Identify target**

If $ARGUMENTS is empty, review the current branch diff (`git diff main...HEAD`).
If $ARGUMENTS is a file path, PR number, or description — use that.

**Step 2 — Dispatch three agents in parallel**

Spawn these three agents simultaneously using the Agent tool:

Every agent brief ends with this **signal filter** (borrowed from Anthropic's `/claude-security`, which drops low-impact noise): *Do NOT report — denial-of-service / resource-exhaustion, rate-limiting gaps, open redirects, or generic "missing input validation" with no demonstrated exploit path. Only report a finding you can tie to a concrete failure or attack.*

**Agent 1 — Security Reviewer**
> Read the target. Find: injection vulnerabilities, auth/authz gaps, credential exposure, XSS, CSRF, insecure defaults, dangerous shell patterns, hardcoded secrets, missing input validation. Produce: MUST FIX / SHOULD FIX findings with file:line evidence. Security issues only — ignore style and performance. [signal filter]

**Agent 2 — Performance Reviewer**
> Read the target. Find: N+1 queries, missing indexes, unnecessary re-renders, blocking I/O in hot paths, large bundle additions, memory leaks, expensive operations in loops, missing caching opportunities. Produce: MUST FIX / SHOULD FIX findings with file:line evidence. Performance issues only — ignore security and style. [signal filter]

**Agent 3 — DX / Correctness Reviewer**
> Read the target. Find: logic bugs, incorrect error handling, missing edge cases, poor variable naming, violated conventions, dead code, missing tests for critical paths, API misuse. Produce: MUST FIX / SHOULD FIX findings with file:line evidence. Correctness and developer experience only — ignore security and performance. [signal filter]

**Step 3 — Adversarially verify each finding** (borrowed from `/claude-security`'s verification panel)

Before synthesizing, stress-test every MUST FIX finding through three lenses. Read the actual code to answer — do not take the reviewer's word:

- **REACHABILITY** — can this code actually run with attacker/caller-controlled input, or is it dead / guarded / test-only?
- **IMPACT** — what concretely goes wrong (data loss, RCE, wrong result, measurable slowdown)? If you can't name it, it's not a MUST FIX.
- **DEFENSES** — does an existing check, type, framework guarantee, or caller contract already neutralize it?

Verdict per finding: **CONFIRMED** (survives all three) → keep at stated severity; **DOWNGRADE** (reachable but low/uncertain impact, or a partial defense exists) → drop a severity tier and mark confidence; **DROP** (unreachable, no impact, or already defended) → remove, with a one-line note in a "Filtered" list. A finding raised by only ONE lens-agent and not independently confirmable → cap confidence at MEDIUM.

**Step 4 — Synthesize**

After verification:

1. Collect the CONFIRMED / DOWNGRADED MUST FIX findings across agents
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

### Filtered (verification dropped/downgraded)
[one line each: finding — why (unreachable / no impact / already defended)]

### Summary
- Total MUST FIX: N (confirmed)
- Total SHOULD FIX: N
- Cross-lens: N
- Filtered by verification: N
```
