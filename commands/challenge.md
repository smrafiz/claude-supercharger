Stress-test this decision: $ARGUMENTS

Be adversarial. The goal is to find the flaw that would sink this, not to confirm it. But do not manufacture problems: "no real blocker found" is an allowed, honest outcome.

Design sources: Klein's pre-mortem (prospective hindsight), the CIA Tradecraft Primer (key assumptions check, analysis of competing hypotheses), Roger Martin's "what would have to be true", Bezos one-way / two-way doors, Annie Duke's kill criteria, Munger's inversion — and the LLM evidence on why critique goes wrong: sycophancy (Anthropic, arXiv 2310.13548), self-correction without an external signal making answers worse (arXiv 2310.01798), and same-context critique agreeing with itself (arXiv 2502.08788).

**Two rules for every step**
- **Evidence or a tag.** Every claim cites what it rests on — `file:line`, command output, a doc — or is marked `unverified`. An LLM critiquing from memory produces generic risk; reading the code is the external signal that makes critique work.
- **The specificity test.** A finding must name a mechanism, the condition that triggers it, and the component it lives in. If it would be equally true of any other plan ("may not scale", "consider edge cases", "security implications"), cut it.

**Step 1 — Restate and classify**
State the decision in one sentence, exactly as decided, not as interpreted. Then classify it:
- **Two-way door** — cheap to reverse (a flag, a local refactor, a config value). Run the short path: Steps 2, 4 and 8 only.
- **One-way door** — expensive or impossible to reverse (a schema or data migration, a public API or wire format, a dependency others build on, a deletion, anything shipped to users). Run every step.

**Step 2 — Ground it (read-only)**
Read what the decision touches: the relevant code, `CLAUDE.md`, ADRs, recent commits (`git log`) and any earlier attempt at the same thing. Run read-only commands where a fact can be checked instead of assumed. List what you could NOT check — everything later may only rely on what this step established or on something tagged `unverified`.

**Step 3 — What would have to be true**
List the conditions that must hold for this to be a good decision. For each: how confident you are, what would prove it false, and the damage if it is false. Flag the **barrier** — the load-bearing condition least likely to be true. It is the thing to check before anything else.

**Step 4 — Pre-mortem, in the past tense**
"It is six months from now. This decision failed. Here is why." Write exactly three causes. Generate them by inversion — how would you *guarantee* this fails? — then keep the three most plausible. Each one: mechanism · trigger · component · evidence or `unverified`. If fewer than three survive the specificity test, report fewer and say so.

**Step 5 — Strongest alternative**
Build the best rival approach in its strongest form (steelman it — how would its best advocate argue?). Then work the other way: what evidence would be *inconsistent* with the chosen approach? The option contradicted by the least evidence wins, not the one with the most support.

**Step 6 — Independent critic** (one-way doors)
Dispatch a fresh read-only agent. Give it only the decision, the files involved and the Step 2 findings — never this analysis or the reasoning behind the decision, which it would anchor on. Instruct it to return the single strongest objection, grounded in the code, or say plainly "no blocker found". It must not soften a real problem to be agreeable, and must not invent one to look thorough.

**Step 7 — Blind spots**
What this analysis did not examine: a stakeholder, a caller, a deploy path, an operational cost, a failure of the rollback itself. Grounded, or marked speculative.

**Step 8 — Verdict and kill criteria**
- **PROCEED** · **RECONSIDER** · **NEEDS MORE INFO** — with one sentence of why.
- **Kill criteria**: 1–3 tripwires decided now, while judgment is clear — an observable signal, a threshold and a date that mean stop or revisit (e.g. "p95 above 400 ms in the first week of rollout", "more than 2 migration retries"). A verdict with no tripwire cannot be proven wrong later.
- NEEDS MORE INFO names the exact fact to go get, and how.

**Output format:**
```
DECISION: [one sentence] · [TWO-WAY DOOR | ONE-WAY DOOR]
GROUNDED IN: [files read, commands run] · NOT VERIFIED: [...]

WHAT WOULD HAVE TO BE TRUE:
| condition | confidence | falsified by | if false |
BARRIER: [the least-likely load-bearing condition]

PRE-MORTEM (it failed because):
1. [mechanism] — trigger: [...] — in: [component] — [evidence | unverified]
2. ...
3. ...

STRONGEST ALTERNATIVE: [steelmanned] · evidence against the chosen approach: [...]

INDEPENDENT CRITIC: [strongest grounded objection | no blocker found]
BLIND SPOTS: [...]

VERDICT: [PROCEED | RECONSIDER | NEEDS MORE INFO] — [one sentence]
KILL CRITERIA: [signal · threshold · by when]
```
