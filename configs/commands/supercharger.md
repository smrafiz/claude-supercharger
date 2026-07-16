List all Claude Supercharger slash commands. Arguments: $ARGUMENTS

Print this table exactly:

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

  Meta
    /sc             Activate / deactivate Supercharger (off | on | status) — flip to default Claude
    /sc-autopilot   Time-boxed auto-approve — skip permission prompts for a duration (safety hooks stay on)
    /sc-readonly    Time-boxed read-only — block edits + mutating commands for a duration (look, don't touch)
    /sc-strict      Time-boxed strict — auto-approve nothing; confirm every call (overrides autopilot)
    /sc-status      Render current Supercharger session state (cost, lessons, disabled hooks)
    /supercharger   This screen
    /sc-update      Check for and apply Supercharger updates
```

No further output. If the user passes `$ARGUMENTS`, check if it matches a command name and give a one-line description of that command only.
