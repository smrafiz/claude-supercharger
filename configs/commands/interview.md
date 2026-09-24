Gather requirements before planning: $ARGUMENTS

Do NOT write any code or create an implementation plan. This is a requirements gate.

It draws out what the **user** wants — the ambiguity is in their head, not in the code. If the problem is that the request itself can be read several ways, that is `/think`. The brief this produces feeds `/scope` (files and approval) and `/estimate` (size).

Design sources: Rob Fitzpatrick's *The Mom Test* (ask about past behaviour and specifics, never opinions or hypotheticals), Jobs-to-be-Done switch interviews (the struggling moment, why now), Matt Wynne's example mapping (rules, examples, open questions), EARS requirement syntax and AWS Kiro specs, ISO/IEC 25010 quality characteristics, GitHub spec-kit `/clarify` (at most five questions, ranked by impact × uncertainty), obra/superpowers brainstorming (read the project first; one question per message), Matt Pocock's grill-me (always propose an answer), ClarifyGPT (ask only where readings diverge), and the evidence that agents both under-ask — filling gaps with invented answers — and over-ask on clear requests.

Use the `AskUserQuestion` tool for EVERY question. Never ask questions as plain prose.

**Step 0 — Read the repo first**
Stack, existing patterns, recent commits (`git log`), any spec, README or docs on this area. Anything the repo settles is KNOWN (cite `file:line`) and is **never asked**. Asking what the code already answers wastes the user's time and signals you didn't look.

**Step 1 — Find the gaps**
Score each area Clear / Partial / Missing using what Step 0 established:

1. **Problem** — the real pain, who has it, why now
2. **Users** — who or what uses this; roles that differ
3. **Success** — observable outcomes, with a concrete example each
4. **Data** — entities, relationships, identity, scale
5. **Flow** — main path, error and empty states, accessibility (if user-facing)
6. **Quality needs** — performance, reliability, security, compatibility, observability
7. **Constraints** — must-nots, systems to respect, rejected alternatives
8. **Integrations** — external services, formats, versions, their failure modes
9. **Edge cases** — limits, conflicts, bad input
10. **Done** — how anyone will know it is finished

Rank the Partial and Missing areas by **impact × uncertainty**: how much a wrong guess would cost, times how unsure you are. **If nothing important is open, ask nothing** — write the brief. Zero questions is a valid outcome.

**Step 2 — Ask, one question at a time**
Wait for each answer before the next. Every question:
- carries a proposed answer, marked **(recommended)**, and one line on why it matters — the decision it unblocks;
- offers discrete options, not "tell me more";
- asks about **what actually happens or happened**, not opinions or hypotheticals: "the last time this broke, what did you do?" or "how is this handled today?" beats "would you want…?" or "do you think…?". People answer hypotheticals optimistically and past events accurately.

For each success criterion, ask for one concrete example — a real scenario. Anything the user cannot answer is an **open question**; log it, don't guess it.

**Step 3 — Quality sweep**
One multiple-choice question: which of these matter here — performance, reliability, security, compatibility, usability/accessibility, maintainability, portability, safety? Follow up only on the ones chosen.

**Step 4 — Stop**
Stop when any of these holds:
- every high-impact area is Clear;
- you can already predict the next answer;
- the user says to go ahead;
- you have asked **5** questions — past that, answers get shallow. Record what is still open.

**Step 5 — Write the brief and hand off**
Output the brief, then invoke `/scope` if the design is clear, or the `superpowers:brainstorming` skill if it is not.

Output format:
```
REQUIREMENTS BRIEF

Problem: [one sentence — the actual pain, from what the user described happening]
Why now: [the trigger | n/a]
Users: [who and what they need]

Already known from the repo:
  - [fact — file:line]

Success criteria (testable):
  - When [trigger], the system shall [response]
  - Given [context] When [action] Then [observable result]

Quality needs: [characteristic — target | best effort]

Constraints:
  - [hard constraint]

Non-goals:
  - [explicitly not this iteration]

Assumptions (unverified — would change the scope if wrong):
  - [...]

Open questions (nobody could answer yet):
  - [... | none]

NEXT: /scope | superpowers:brainstorming
```
