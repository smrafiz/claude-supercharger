---
description: "Pick the right Supercharger command for a situation, or list them all."
argument-hint: "[situation]"
---
Route to the right Supercharger command, or list them all. Arguments: $ARGUMENTS

There are more user-invoked commands than anyone holds in their head, so this screen has
two jobs: an index when you want to browse, and a router when you already have a
problem and don't want to scan a list to name it.

## If `$ARGUMENTS` is empty — print this table exactly, then stop

```
Claude Supercharger — Slash Commands

  Code & Review
    /sc-audit          Sweep project for naming, pattern, doc, and structure inconsistencies
    /sc-security       OWASP-style security review of current changes
    /sc-multi-review   Run multiple review passes (correctness, perf, security, style)
    /sc-challenge      Devil's advocate — stress-test a decision or approach
    /sc-think          Force deep reasoning on a hard problem before acting

  Workflow
    /sc-scope          Pre-flight gate — confirm scope, risks, and stop conditions before starting
    /sc-estimate       Time + complexity estimate (report-only, no work started)
    /sc-cleanup        Dead code + unused-import removal (two-tier safety: auto-fix safe, gate risky)
    /sc-pr             One-step pull request (summary + test plan + gh pr create)
    /sc-resolve-conflicts  Resolve an in-progress merge/rebase conflict (recover intent, verify, finish)
    /sc-handoff        Session resume brief — decisions, files changed, next steps
    /sc-devlog         Update living architecture journal with what changed and why
    /sc-interview      Structured requirements gathering, one question at a time

  Design
    /sc-design         Write DESIGN.md — brand tokens read from the project's own theme
    /sc-design-review  UI review — WCAG 2.2 AA with measured values, hierarchy, 3 viewports
    /sc-reflect        Post-task retrospective — what worked, what to improve

  Diagnostics
    /sc-stuck          Break a debug loop — fresh eyes, new hypothesis
    /sc-why            Explain the most recent Supercharger hook action
    /sc-perf           Hook timing report with slowdown suggestions
    /sc-cache-stats    Typecheck + quality-gate cache state
    /sc-cache-clear    Clear hash caches (forces full re-check on next run)
    /sc-profile        Show or switch performance profile (standard / fast / minimal)

  Memory
    /sc-learn          Record an explicit project rule (surfaces on future prompts)
    /sc-memory-prune   Archive resolved memory entries so they stop loading every session

  Meta
    /sc             Activate / deactivate Supercharger (off | on | status) — flip to default Claude
    /sc-autopilot   Time-boxed auto-approve — skip permission prompts for a duration (safety hooks stay on)
    /sc-readonly    Time-boxed read-only — block edits + mutating commands for a duration (look, don't touch)
    /sc-strict      Time-boxed strict — auto-approve nothing; confirm every call (overrides autopilot)
    /sc-status      Render current Supercharger session state (cost, lessons, disabled hooks)
    /sc-trust-mcp      Trust an MCP server to request credentials via Elicitation forms
    /supercharger   This screen — pass a situation to route instead of browse
    /sc-update      Check for and apply Supercharger updates
    /sc-doctor      Diagnose the install — registration, integrity, permissions, update status
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
| "is this safe to ship", "check my changes for vulns" | `/sc-security` | `/sc-audit` — that's consistency, not vulnerabilities |
| "review this properly", "what did I miss" | `/sc-multi-review` | `/sc-security` unless they said security |
| "the codebase feels inconsistent", "naming is a mess" | `/sc-audit` | `/sc-cleanup` — that deletes, this reports |
| "remove dead code", "unused imports" | `/sc-cleanup` | `/sc-audit` |
| "am I sure about this decision", "poke holes in this" | `/sc-challenge` | `/sc-think` — that reasons, this attacks |
| "this is hard, don't rush it" | `/sc-think` | |
| "I've been stuck on this bug for ages", "same error again" | `/sc-stuck` | `/sc-think` — a debug loop needs a new hypothesis, not more reasoning |
| "why was that blocked", "what fired" | `/sc-why` | |
| "before we start", "what's in scope" | `/sc-scope` | `/sc-interview` — that gathers, this gates |
| "I don't know what I want yet" | `/sc-interview` | `/sc-scope` |
| "how long will this take" | `/sc-estimate` | |
| "open a PR", "ship this" | `/sc-pr` | |
| "I have merge conflicts", "rebase blew up" | `/sc-resolve-conflicts` | `/sc-stuck` — that is for debug loops, not conflicts |
| "I'm running out of context", "continue tomorrow" | `/sc-handoff` | |
| "record why we did it this way" | `/sc-devlog` | `/sc-learn` — that's a rule, this is history |
| "remember this rule for next time" | `/sc-learn` | `/sc-devlog` |
| "does this UI work", "accessibility" | `/sc-design-review` | `/sc-design` — that writes the brand brief, it does not review |
| "set up our design tokens", "brand brief" | `/sc-design` | `/sc-design-review` |
| "how did that session go" | `/sc-reflect` | |
| "Claude keeps asking permission" | `/sc-autopilot` | `/sc` — that removes the safety floor too |
| "don't let it touch anything" | `/sc-readonly` | `/sc-strict` — that still allows edits, just confirms each |
| "confirm every single call" | `/sc-strict` | `/sc-readonly` |
| "turn it all off", "I want plain Claude" | `/sc off` | `/sc-readonly` if they only want to stop edits |
| "what's active right now", "what's this costing" | `/sc-status` | `/sc-perf` — that's hook latency, this is session state |
| "everything feels slow" | `/sc-perf` | `/sc-profile` — check the measurement before switching profile |
| "make it faster" | `/sc-profile` | `/sc-perf` first |
| "context keeps filling up" | `/sc-memory-prune` | |
| "typecheck seems stale", "is it caching" | `/sc-cache-stats` | `/sc-cache-clear` — look before you wipe |
| "force a full re-check" | `/sc-cache-clear` | `/sc-cache-stats` first |
| "an MCP server wants my credentials" | `/sc-trust-mcp` | |
| "update Supercharger" | `/sc-update` | |
| "is my install healthy", "did something break", "guards don't seem to run" | `/sc-doctor` | Ends with one pasteable line — ask for that when helping someone remotely |

### If the situation is a whole JOB, not a single step — return a sequence

Some requests are an arc, not a question. "I want a security audit" is not one command;
it is a scope decision, a review, and a record of what was found. When the situation
matches a workflow below, return the **ordered sequence** instead of a single route:

```
→ /sc-security        1. the core review — diff-scoped, OWASP-anchored
  /sc-multi-review    2. breadth beyond security, if the change is large
  /sc-devlog          3. record what was found and decided
```

Number the steps and say what each contributes. **Cap at four** — past that it stops being
advice and becomes a project plan the user did not ask for. Name only steps that earn
their place for *this* request; a workflow is a starting point, not a checklist to
complete.

| The job | Sequence | Why this order |
|---|---|---|
| Security audit | `/sc-security` → `/sc-multi-review` → `/sc-devlog` | Narrow before broad. `/sc-security` is diff-scoped and cheap; `/sc-multi-review` spawns agents, so only widen if the first pass warrants it |
| Starting a substantial feature | `/sc-interview` → `/sc-scope` → `/sc-estimate` | Requirements before boundaries before time. Estimating an unscoped task is guesswork |
| Inherited or unfamiliar codebase | `/sc-audit` → `/sc-security` → `/sc-cleanup` | Understand shape, then risk, then remove. Deleting before understanding is how you delete something load-bearing |
| Finishing a work session | `/sc-reflect` → `/sc-handoff` | Reflect first — its observations are what makes the handoff worth reading |
| Shipping a change | `/sc-multi-review` → `/sc-pr` → `/sc-devlog` | Review before the PR exists, so the description reflects what survived review |
| Stuck and going in circles | `/sc-stuck` → `/sc-why` | `/sc-stuck` reframes; `/sc-why` only if a guard is involved and the cause is unclear |
| Something feels slow | `/sc-perf` → `/sc-profile` | Measure before switching profile. The measurement usually names a single hook, not a profile problem |

If the request is a single step, do **not** manufacture a sequence — one route is the
better answer, and padding it wastes the user's attention.

### When two look equally right

Prefer the one that **reports** over the one that **changes** — `/sc-audit` before `/sc-cleanup`,
`/sc-perf` before `/sc-profile`, `/sc-estimate` before `/sc-pr`. A wrong report costs a paragraph; a
wrong change costs a revert.
