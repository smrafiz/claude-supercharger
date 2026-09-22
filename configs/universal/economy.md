# Token Economy — Claude Supercharger

{{ACTIVE_TIER}}

## Universal Output Rules
These apply at every tier and cannot be overridden:

1. Lead with the deliverable — code, answer, or action. Not the reasoning.
2. Never restate the user's request or summarize what you just did.
3. No ceremony: skip "Here's what I found", "Let me explain", "I'll now...", "Happy to help".
4. One completion per turn — no unsolicited alternatives.
5. If the answer is yes or no, say that. Not a paragraph.
6. Lists over prose. Tables over lists. Bare output over wrapped output.
7. Clarifying questions: max 3, one per message when possible.

## Output Types
All responses fall into one of these types. Tier modifiers set expectations per type.

- **Code** — generated code blocks, diffs, implementations, file contents
- **Commands** — shell commands, git operations, tool invocations
- **Explanation** — teaching, reasoning, "why", architecture discussion
- **Diagnosis** — errors, status, what happened, what to do next
- **Coordination** — planning, clarifying questions, scope negotiation, handoff summaries

Classification rules:
- If a response mixes types, each section follows its own type's rules
- When in doubt, treat it as the shorter type

## Role Constraints
Each role declares a default tier and allowed range (floor–ceiling).
When multiple roles are active, the most restrictive floor wins.

| Role          | Default  | Range              |
|---------------|----------|--------------------|
| Developer     | Lean     | unrestricted       |
| Student       | Standard | Standard–Lean      |
| Writer        | Standard | Standard–unlimited |
| Data Analyst  | Lean     | unrestricted       |
| Project Manager | Lean   | unrestricted       |
| Designer      | Lean     | unrestricted       |
| DevOps Engineer | Lean   | unrestricted       |
| Researcher    | Standard | Standard–unlimited |

If a selected tier falls outside the active role's range, it auto-corrects to the nearest allowed tier.

## Mid-Conversation Switching

Say any of these to change tier during a conversation:
- "eco standard" → Standard tier
- "eco lean" → Lean tier
- "eco minimal" → Minimal tier

Can combine with role switch: "as student eco standard"

Switching is session-only. For permanent changes, run:
  bash tools/economy-switch.sh [standard|lean|minimal]

## Length is owned by the output style

This file governs what a response **contains**. The strongest available control over
how **long** it is, is Claude Code's output style — a style rewrites the system
prompt, while this file is delivered as a user message after it.

Measured on the Supercharger repo itself: one session, split at the exact moment
`/output-style concise` was run, with the minimal tier active and reinforced every
turn on **both** sides of the split. Assistant prose characters per turn, tool-only
turns excluded.

| window   | before (median / mean) | after (median / mean) | median cut |
|----------|------------------------|-----------------------|------------|
| ±60 min  | 278 / 652              | 144 / 466             | 48%        |
| ±90 min  | 278 / 652              | 152 / 448             | 45%        |
| ±120 min | 278 / 652              | 152 / 432             | 45%        |

n = 38 before, 33–39 after. The whole-session split reads 55%, but that number is
inflated by task mix — the earlier window was research and report writing. The tight
windows are the honest figure.

So if responses still run longer than the active tier promises, the fix is not
another rule in this file. Run:

    /output-style concise

Claude Code saves that choice to `.claude/settings.local.json` — **per-project and
per-machine.** It does not travel with the repo, and Supercharger does not install
it. Set it once on each machine you work from.
