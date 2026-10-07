---
description: "Route to the right Supercharger command, or list them all. Arguments: $ARGUMENTS"
---
Route to the right Supercharger command, or list them all. Arguments: $ARGUMENTS

There are more user-invoked commands than anyone holds in their head, so this screen has
two jobs: an index when you want to browse, and a router when you already have a
problem and don't want to scan a list to name it.

## If `$ARGUMENTS` is empty — print this table exactly, then stop

```
Claude Supercharger — Slash Commands

  Code & Review
    /supercharger:audit          Sweep project for naming, pattern, doc, and structure inconsistencies
    /supercharger:security       OWASP-style security review of current changes
    /supercharger:multi-review   Run multiple review passes (correctness, perf, security, style)
    /supercharger:challenge      Devil's advocate — stress-test a decision or approach
    /supercharger:think          Force deep reasoning on a hard problem before acting

  Workflow
    /supercharger:scope          Pre-flight gate — confirm scope, risks, and stop conditions before starting
    /supercharger:estimate       Time + complexity estimate (report-only, no work started)
    /supercharger:cleanup        Dead code + unused-import removal (two-tier safety: auto-fix safe, gate risky)
    /supercharger:pr             One-step pull request (summary + test plan + gh pr create)
    /supercharger:resolve-conflicts  Resolve an in-progress merge/rebase conflict (recover intent, verify, finish)
    /supercharger:handoff        Session resume brief — decisions, files changed, next steps
    /supercharger:devlog         Update living architecture journal with what changed and why
    /supercharger:interview      Structured requirements gathering, one question at a time

  Design
    /supercharger:design         Write DESIGN.md — brand tokens read from the project's own theme
    /supercharger:design-review  UI review — WCAG 2.2 AA with measured values, hierarchy, 3 viewports
    /supercharger:reflect        Post-task retrospective — what worked, what to improve

  Diagnostics
    /supercharger:stuck          Break a debug loop — fresh eyes, new hypothesis
    /supercharger:why            Explain the most recent Supercharger hook action
    /supercharger:perf           Hook timing report with slowdown suggestions
    /supercharger:cache-stats    Typecheck + quality-gate cache state
    /supercharger:cache-clear    Clear hash caches (forces full re-check on next run)
    /supercharger:profile        Show or switch performance profile (standard / fast / minimal)

  Memory
    /supercharger:learn          Record an explicit project rule (surfaces on future prompts)
    /supercharger:memory-prune   Archive resolved memory entries so they stop loading every session

  Meta
    /sc             Activate / deactivate Supercharger (off | on | status) — flip to default Claude
    /supercharger:autopilot   Time-boxed auto-approve — skip permission prompts for a duration (safety hooks stay on)
    /supercharger:readonly    Time-boxed read-only — block edits + mutating commands for a duration (look, don't touch)
    /supercharger:strict      Time-boxed strict — auto-approve nothing; confirm every call (overrides autopilot)
    /supercharger:status      Render current Supercharger session state (cost, lessons, disabled hooks)
    /supercharger:trust-mcp      Trust an MCP server to request credentials via Elicitation forms
    /supercharger   This screen — pass a situation to route instead of browse
    /supercharger:update      Check for and apply Supercharger updates
    /supercharger:doctor      Diagnose the install — registration, integrity, permissions, update status
```

Then add one line: `Tip: /supercharger <what you're trying to do> routes you instead.`

## If `$ARGUMENTS` names a command — one-line description of that command only

## Otherwise `$ARGUMENTS` is a SITUATION — route it

Answer in this shape, nothing else:

```
→ /command          — why this one, in one clause
  /other-command    — when you'd want this instead
```

Name **one primary** command and **at most two** alternates. Never list more; a router
that returns five options has just rebuilt the index the user was avoiding. If nothing
fits, say so plainly and suggest the closest thing — do not invent a command.

### Routing table — match on the user's SITUATION, not on keywords

| They say something like | Route to | Not to |
|---|---|---|
| "is this safe to ship", "check my changes for vulns" | `/supercharger:security` | `/supercharger:audit` — that's consistency, not vulnerabilities |
| "review this properly", "what did I miss" | `/supercharger:multi-review` | `/supercharger:security` unless they said security |
| "the codebase feels inconsistent", "naming is a mess" | `/supercharger:audit` | `/supercharger:cleanup` — that deletes, this reports |
| "remove dead code", "unused imports" | `/supercharger:cleanup` | `/supercharger:audit` |
| "am I sure about this decision", "poke holes in this" | `/supercharger:challenge` | `/supercharger:think` — that reasons, this attacks |
| "this is hard, don't rush it" | `/supercharger:think` | |
| "I've been stuck on this bug for ages", "same error again" | `/supercharger:stuck` | `/supercharger:think` — a debug loop needs a new hypothesis, not more reasoning |
| "why was that blocked", "what fired" | `/supercharger:why` | |
| "before we start", "what's in scope" | `/supercharger:scope` | `/supercharger:interview` — that gathers, this gates |
| "I don't know what I want yet" | `/supercharger:interview` | `/supercharger:scope` |
| "how long will this take" | `/supercharger:estimate` | |
| "open a PR", "ship this" | `/supercharger:pr` | |
| "I have merge conflicts", "rebase blew up" | `/supercharger:resolve-conflicts` | `/supercharger:stuck` — that is for debug loops, not conflicts |
| "I'm running out of context", "continue tomorrow" | `/supercharger:handoff` | |
| "record why we did it this way" | `/supercharger:devlog` | `/supercharger:learn` — that's a rule, this is history |
| "remember this rule for next time" | `/supercharger:learn` | `/supercharger:devlog` |
| "does this UI work", "accessibility" | `/supercharger:design-review` | `/supercharger:design` — that writes the brand brief, it does not review |
| "set up our design tokens", "brand brief" | `/supercharger:design` | `/supercharger:design-review` |
| "how did that session go" | `/supercharger:reflect` | |
| "Claude keeps asking permission" | `/supercharger:autopilot` | `/sc` — that removes the safety floor too |
| "don't let it touch anything" | `/supercharger:readonly` | `/supercharger:strict` — that still allows edits, just confirms each |
| "confirm every single call" | `/supercharger:strict` | `/supercharger:readonly` |
| "turn it all off", "I want plain Claude" | `/sc off` | `/supercharger:readonly` if they only want to stop edits |
| "what's active right now", "what's this costing" | `/supercharger:status` | `/supercharger:perf` — that's hook latency, this is session state |
| "everything feels slow" | `/supercharger:perf` | `/supercharger:profile` — check the measurement before switching profile |
| "make it faster" | `/supercharger:profile` | `/supercharger:perf` first |
| "context keeps filling up" | `/supercharger:memory-prune` | |
| "typecheck seems stale", "is it caching" | `/supercharger:cache-stats` | `/supercharger:cache-clear` — look before you wipe |
| "force a full re-check" | `/supercharger:cache-clear` | `/supercharger:cache-stats` first |
| "an MCP server wants my credentials" | `/supercharger:trust-mcp` | |
| "update Supercharger" | `/supercharger:update` | |
| "is my install healthy", "did something break", "guards don't seem to run" | `/supercharger:doctor` | Ends with one pasteable line — ask for that when helping someone remotely |

### If the situation is a whole JOB, not a single step — return a sequence

Some requests are an arc, not a question. "I want a security audit" is not one command;
it is a scope decision, a review, and a record of what was found. When the situation
matches a workflow below, return the **ordered sequence** instead of a single route:

```
→ /supercharger:security        1. the core review — diff-scoped, OWASP-anchored
  /supercharger:multi-review    2. breadth beyond security, if the change is large
  /supercharger:devlog          3. record what was found and decided
```

Number the steps and say what each contributes. **Cap at four** — past that it stops being
advice and becomes a project plan the user did not ask for. Name only steps that earn
their place for *this* request; a workflow is a starting point, not a checklist to
complete.

| The job | Sequence | Why this order |
|---|---|---|
| Security audit | `/supercharger:security` → `/supercharger:multi-review` → `/supercharger:devlog` | Narrow before broad. `/supercharger:security` is diff-scoped and cheap; `/supercharger:multi-review` spawns agents, so only widen if the first pass warrants it |
| Starting a substantial feature | `/supercharger:interview` → `/supercharger:scope` → `/supercharger:estimate` | Requirements before boundaries before time. Estimating an unscoped task is guesswork |
| Inherited or unfamiliar codebase | `/supercharger:audit` → `/supercharger:security` → `/supercharger:cleanup` | Understand shape, then risk, then remove. Deleting before understanding is how you delete something load-bearing |
| Finishing a work session | `/supercharger:reflect` → `/supercharger:handoff` | Reflect first — its observations are what makes the handoff worth reading |
| Shipping a change | `/supercharger:multi-review` → `/supercharger:pr` → `/supercharger:devlog` | Review before the PR exists, so the description reflects what survived review |
| Stuck and going in circles | `/supercharger:stuck` → `/supercharger:why` | `/supercharger:stuck` reframes; `/supercharger:why` only if a guard is involved and the cause is unclear |
| Something feels slow | `/supercharger:perf` → `/supercharger:profile` | Measure before switching profile. The measurement usually names a single hook, not a profile problem |

If the request is a single step, do **not** manufacture a sequence — one route is the
better answer, and padding it wastes the user's attention.

### When two look equally right

Prefer the one that **reports** over the one that **changes** — `/supercharger:audit` before `/supercharger:cleanup`,
`/supercharger:perf` before `/supercharger:profile`, `/supercharger:estimate` before `/supercharger:pr`. A wrong report costs a paragraph; a
wrong change costs a revert.
