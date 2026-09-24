Add an entry to the project's DEV-LOG.md: $ARGUMENTS

DEV-LOG.md is a living architecture journal — a running log of non-obvious decisions, context that isn't in the code, and rationale that git commit messages can't hold. It is NOT a changelog. It captures the WHY.

Design sources: Michael Nygard's architecture decision records and MADR (status, alternatives, consequences, supersede rather than edit), Olaf Zimmermann's Y-statements, arc42 §9 (record only architecturally significant decisions), Keep a Changelog and Diátaxis (a changelog lists *what* shipped; this log *explains why*), and the known risk of agent-written docs: rationale that sounds right but was never actually stated.

**Where a fact belongs** — check before writing:

| If it is… | It goes in… |
|---|---|
| what changed, fully explained by the diff | the commit message |
| what shipped in a release, for users | the changelog |
| a rule the agent must follow from now on | `/learn` or `CLAUDE.md` |
| where this session got to, how to resume | `/handoff` |
| **why the system is built this way — a decision with real alternatives and lasting consequences** | **here** |

If the project keeps formal ADRs (`docs/adr/`, `doc/adr/`, `adr/`), a significant decision gets a new ADR in that format; use this log only for lighter context.

**Step 0 — Is this worth an entry?**
Worth it when the decision changes structure, a dependency, an interface or a quality attribute (performance, security, reliability), or when real alternatives were weighed, or when a newcomer would reasonably ask "why is it done this way?". If the change is routine and its commit message already explains it, say so and stop — an entry that restates the diff is noise that buries the entries that matter.

**Step 1 — Locate or create DEV-LOG.md**
Check if `DEV-LOG.md` exists in the project root. If not, create it with a header:
```
# DEV-LOG

Running log of architectural decisions, non-obvious context, and rationale.
Most recent entries at the top. Append-only: a reversed decision gets a new entry that supersedes the old one.
```

**Step 2 — Gather evidence**
Find the change with `git log` / `git show` and collect what explains it: commit messages, PR and issue text, and what the user actually said in this conversation. **The Why must come from one of these.** If none of them states a reason, do not supply one — ask the user, or write "rationale not recorded". A confident, plausible reason nobody gave is worse than none: it will be believed.

**Step 3 — Supersede or add?**
Search the log for an entry on the same subject. If this decision reverses or replaces one, the new entry names it, and the old entry gets exactly one change: its status becomes `Superseded by YYYY-MM-DD — [title]`. Never rewrite an old entry's content — the log is only trustworthy if history stays history.

**Step 4 — Write the entry**
Take the date from the system or the commit, not from memory. Keep it scannable — about ten lines; link to commits and PRs rather than pasting detail.

Format:
```
## YYYY-MM-DD — [short title: what this is about] · Status: Accepted

**What:** [1-2 sentences describing the decision or change — not the diff]

**Why:** [the reason — constraint, incident, stakeholder requirement, tradeoff chosen]
[Optional one-line form: In the context of X, facing Y, we chose Z to achieve Q, accepting W.]

**Rejected:** [what was considered but not chosen, and why — omit if nothing notable]

**Evidence:** [commit shas · PR #N · issue #N · "user, YYYY-MM-DD: …"]
```

Status is `Accepted` by default; `Proposed` for a decision not yet made final.

Prepend the new entry (most recent at top). Do not modify existing entries except for a supersession marker.

**Step 5 — Confirm**
State the entry path, the title added, the evidence it cites, and any entry it superseded. If you stopped at Step 0, say where the fact belongs instead.
