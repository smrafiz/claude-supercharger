Route to the right Supercharger command, or list them all. Arguments: $ARGUMENTS

There are more user-invoked commands than anyone holds in their head, so this screen has
two jobs: an index when you want to browse, and a router when you already have a
problem and don't want to scan a list to name it.

## If `$ARGUMENTS` is empty — print this table exactly, then stop

```
Claude Supercharger — Slash Commands

  Code & Review
    /audit          Sweep project for naming, pattern, doc, and structure inconsistencies
    /security       OWASP-style security review of current changes
    /multi-review   Run multiple review passes (correctness, perf, security, style)
    /challenge      Devil's advocate — stress-test a decision or approach
    /think          Force deep reasoning on a hard problem before acting

  Workflow
    /scope          Pre-flight gate — confirm scope, risks, and stop conditions before starting
    /estimate       Time + complexity estimate (report-only, no work started)
    /cleanup        Dead code + unused-import removal (two-tier safety: auto-fix safe, gate risky)
    /pr             One-step pull request (summary + test plan + gh pr create)
    /resolve-conflicts  Resolve an in-progress merge/rebase conflict (recover intent, verify, finish)
    /handoff        Session resume brief — decisions, files changed, next steps
    /devlog         Update living architecture journal with what changed and why
    /interview      Structured requirements gathering, one question at a time

  Design
    /design         UI/UX design review — accessibility, hierarchy, responsiveness
    /reflect        Post-task retrospective — what worked, what to improve

  Diagnostics
    /stuck          Break a debug loop — fresh eyes, new hypothesis
    /why            Explain the most recent Supercharger hook action
    /perf           Hook timing report with slowdown suggestions
    /cache-stats    Typecheck + quality-gate cache state
    /cache-clear    Clear hash caches (forces full re-check on next run)
    /profile        Show or switch performance profile (standard / fast / minimal)

  Memory
    /learn          Record an explicit project rule (surfaces on future prompts)
    /memory-prune   Archive resolved memory entries so they stop loading every session

  Meta
    /sc             Activate / deactivate Supercharger (off | on | status) — flip to default Claude
    /sc-autopilot   Time-boxed auto-approve — skip permission prompts for a duration (safety hooks stay on)
    /sc-readonly    Time-boxed read-only — block edits + mutating commands for a duration (look, don't touch)
    /sc-strict      Time-boxed strict — auto-approve nothing; confirm every call (overrides autopilot)
    /sc-status      Render current Supercharger session state (cost, lessons, disabled hooks)
    /trust-mcp      Trust an MCP server to request credentials via Elicitation forms
    /supercharger   This screen — pass a situation to route instead of browse
    /sc-update      Check for and apply Supercharger updates
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
| "is this safe to ship", "check my changes for vulns" | `/security` | `/audit` — that's consistency, not vulnerabilities |
| "review this properly", "what did I miss" | `/multi-review` | `/security` unless they said security |
| "the codebase feels inconsistent", "naming is a mess" | `/audit` | `/cleanup` — that deletes, this reports |
| "remove dead code", "unused imports" | `/cleanup` | `/audit` |
| "am I sure about this decision", "poke holes in this" | `/challenge` | `/think` — that reasons, this attacks |
| "this is hard, don't rush it" | `/think` | |
| "I've been stuck on this bug for ages", "same error again" | `/stuck` | `/think` — a debug loop needs a new hypothesis, not more reasoning |
| "why was that blocked", "what fired" | `/why` | |
| "before we start", "what's in scope" | `/scope` | `/interview` — that gathers, this gates |
| "I don't know what I want yet" | `/interview` | `/scope` |
| "how long will this take" | `/estimate` | |
| "open a PR", "ship this" | `/pr` | |
| "I have merge conflicts", "rebase blew up" | `/resolve-conflicts` | `/stuck` — that is for debug loops, not conflicts |
| "I'm running out of context", "continue tomorrow" | `/handoff` | |
| "record why we did it this way" | `/devlog` | `/learn` — that's a rule, this is history |
| "remember this rule for next time" | `/learn` | `/devlog` |
| "does this UI work", "accessibility" | `/design` | |
| "how did that session go" | `/reflect` | |
| "Claude keeps asking permission" | `/sc-autopilot` | `/sc` — that removes the safety floor too |
| "don't let it touch anything" | `/sc-readonly` | `/sc-strict` — that still allows edits, just confirms each |
| "confirm every single call" | `/sc-strict` | `/sc-readonly` |
| "turn it all off", "I want plain Claude" | `/sc off` | `/sc-readonly` if they only want to stop edits |
| "what's active right now", "what's this costing" | `/sc-status` | `/perf` — that's hook latency, this is session state |
| "everything feels slow" | `/perf` | `/profile` — check the measurement before switching profile |
| "make it faster" | `/profile` | `/perf` first |
| "context keeps filling up" | `/memory-prune` | |
| "typecheck seems stale", "is it caching" | `/cache-stats` | `/cache-clear` — look before you wipe |
| "force a full re-check" | `/cache-clear` | `/cache-stats` first |
| "an MCP server wants my credentials" | `/trust-mcp` | |
| "update Supercharger" | `/sc-update` | |

### If the situation is a whole JOB, not a single step — return a sequence

Some requests are an arc, not a question. "I want a security audit" is not one command;
it is a scope decision, a review, and a record of what was found. When the situation
matches a workflow below, return the **ordered sequence** instead of a single route:

```
→ /security        1. the core review — diff-scoped, OWASP-anchored
  /multi-review    2. breadth beyond security, if the change is large
  /devlog          3. record what was found and decided
```

Number the steps and say what each contributes. **Cap at four** — past that it stops being
advice and becomes a project plan the user did not ask for. Name only steps that earn
their place for *this* request; a workflow is a starting point, not a checklist to
complete.

| The job | Sequence | Why this order |
|---|---|---|
| Security audit | `/security` → `/multi-review` → `/devlog` | Narrow before broad. `/security` is diff-scoped and cheap; `/multi-review` spawns agents, so only widen if the first pass warrants it |
| Starting a substantial feature | `/interview` → `/scope` → `/estimate` | Requirements before boundaries before time. Estimating an unscoped task is guesswork |
| Inherited or unfamiliar codebase | `/audit` → `/security` → `/cleanup` | Understand shape, then risk, then remove. Deleting before understanding is how you delete something load-bearing |
| Finishing a work session | `/reflect` → `/handoff` | Reflect first — its observations are what makes the handoff worth reading |
| Shipping a change | `/multi-review` → `/pr` → `/devlog` | Review before the PR exists, so the description reflects what survived review |
| Stuck and going in circles | `/stuck` → `/why` | `/stuck` reframes; `/why` only if a guard is involved and the cause is unclear |
| Something feels slow | `/perf` → `/profile` | Measure before switching profile. The measurement usually names a single hook, not a profile problem |

If the request is a single step, do **not** manufacture a sequence — one route is the
better answer, and padding it wastes the user's attention.

### When two look equally right

Prefer the one that **reports** over the one that **changes** — `/audit` before `/cleanup`,
`/perf` before `/profile`, `/estimate` before `/pr`. A wrong report costs a paragraph; a
wrong change costs a revert.
