# Claude Supercharger — More Examples

These examples show how Supercharger changes Claude Code behavior across different roles and features. See [README](../README.md) for install instructions.

---

## Safety Hooks

**Your prompt:** "Clean up the old build files"

**Before:**
> Running `rm -rf /` to clean up... (catastrophic)

**After:**
> BLOCKED by Supercharger safety hook: destructive command detected.
> Let me use a safer approach: `rm -rf ./dist/` to remove only the build output directory.

---

## Role: Developer

**Your prompt:** "How do I center a div?"

**Before:**
> There are several ways to center a div in CSS. Let me explain the history of centering in web development, starting with the table-based layouts of the 1990s... (500 words later) ...here's the code.

**After:**
> ```css
> .container { display: grid; place-items: center; }
> ```

---

## Role: Writer

**Your prompt:** "Write an intro for our product launch blog post"

**Before:**
> In today's rapidly evolving technological landscape, we are thrilled to announce the launch of our groundbreaking new product that will revolutionize the way you think about productivity...

**After:**
> Before I draft, two quick questions:
> 1. Who's the audience — existing users or new prospects?
> 2. What tone — formal announcement or casual/excited?
>
> Here are 3 opening options once I know:
> - **A (Direct):** "Starting today, [Product] does X. Here's what that means for your workflow."
> - **B (Story):** "Last month, a customer asked us why X was so hard. We didn't have a good answer. Now we do."
> - **C (Data):** "Teams using [Product] ship 40% faster. Today's update makes that gap wider."

---

## Role: Data

**Your prompt:** "Analyze the sales data"

**Before:**
> Sales are increasing. Q3 was better than Q2. Revenue is up.

**After:**
> **Key finding:** Q3 revenue grew 23% vs Q2, but this is driven entirely by Enterprise tier (+41%). SMB revenue declined 8%.
>
> | Segment | Q2 | Q3 | Change |
> |---------|-----|-----|--------|
> | Enterprise | $1.2M | $1.7M | +41% |
> | SMB | $800K | $736K | -8% |
> | Total | $2.0M | $2.4M | +23% |
>
> **Assumptions:** Revenue = recognized, not booked. Currency: USD. Source: `sales_q2q3_2026.csv`.
>
> **Caveat:** SMB sample size is small (n=47). The -8% decline is not statistically significant (p=0.12). More data needed before concluding a trend.
>
> Query used: `SELECT segment, quarter, SUM(revenue) FROM sales GROUP BY segment, quarter`

---

## Role: PM

**Your prompt:** "How long will the auth migration take?"

**Before:**
> The auth migration should take about 2 weeks.

**After:**
> **Estimate (range):**
> - Optimistic: 5 days (no blockers, clean data migration)
> - Likely: 8 days (1-2 integration issues, testing buffer)
> - Pessimistic: 14 days (legacy edge cases, third-party API changes)
>
> **Assumptions that could change this:**
> - Current session tokens are well-structured (not verified)
> - Third-party OAuth providers don't require re-registration
> - No compliance review required for the new token format
>
> **Risks:**
> - [High] Legacy sessions may not migrate cleanly — suggest a parallel-run period
> - [Medium] OAuth callback URLs may need updating across 3 environments
>
> **Recommendation:** Start with a spike (1 day) to validate the session migration path before committing to the full estimate.

---

## Quick Mode Switch

**Your prompt:** "as student: explain how git rebase works"

**Before:**
> `git rebase` re-applies commits on top of another base tip. Usage: `git rebase <branch>`.

**After:**
> Let's build this up step by step.
>
> Imagine you're writing a book with a friend. You both started from chapter 5. Your friend finished chapters 6-7, and you wrote chapters 6-8 separately. Now you need to combine.
>
> **Merge** is like stapling both versions together with a note saying "combined here."
>
> **Rebase** is like rewriting your chapters 6-8 so they start *after* your friend's chapter 7 — as if you always had their work first.
>
> The result is the same content, but the history looks cleaner.
>
> Want to try it? Create a test repo and I'll walk you through it step by step.

---

## Clarification Mode

**Your prompt:** "interview me — I want to build a dashboard"

**Before:**
> Sure! Here's a React dashboard with charts, tables, and a sidebar navigation... (starts building immediately)

**After:**
> Let's think this through before building anything.
>
> First question: Who will use this dashboard — internal team members, external customers, or both?

(Then asks follow-up questions one at a time about data sources, update frequency, key metrics, access control — and summarizes understanding before writing a single line of code.)

---

## Session Handoff

**Your prompt:** "We're done for today, summarize where we are"

**Before:**
> We worked on some things today. Good progress!

**After:**
> **Session summary — paste this into your next conversation:**
>
> ```
> ## Context (carry forward)
> - Building: auth migration for user-service
> - Stack: Node.js, Express, PostgreSQL, JWT
> - Decisions made: using refresh token rotation, 15min access token TTL
> - Files changed: src/auth/middleware.ts, src/auth/tokens.ts, tests/auth.test.ts
> - Current state: middleware done, token generation done, tests passing (8/8)
> - Left to do: session migration script, OAuth callback updates
> - Blocker: need to verify legacy session token format (check with backend team)
> ```
