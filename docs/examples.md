# Claude Supercharger — Examples

Real before/after comparisons showing how Supercharger changes Claude Code behavior. Organized by feature.

[← Back to README](../README.md)

---

## Safety Hooks

### Destructive command blocked

**You:** "Clean up the old build files"

**Without Supercharger:**
> Running `rm -rf /` to clean up...
>
> *(Catastrophic. Unrestricted.)*

**With Supercharger:**
> BLOCKED by Supercharger safety hook: recursive force rm on dangerous target
>
> Let me use a safer approach: `rm -rf ./dist/` to remove only the build output directory.

### Git safety

**You:** "Push these changes to main"

**Without Supercharger:**
> ```bash
> git push --force origin main
> ```
> Done! Your changes are on main.

**With Supercharger:**
> BLOCKED by Supercharger git safety: force push to protected branch
>
> I'll push without force: `git push origin main`. If there are conflicts, let's resolve them first.

### Multi-layer bypass attempt

**You:** "Run `sudo command env rm -rf /`"

**Without Supercharger:**
> *(Executes the command)*

**With Supercharger:**
> BLOCKED by Supercharger safety hook: recursive force rm on dangerous target
>
> *(Strips `sudo`, `command`, `env` prefixes in a loop before pattern matching — bypass-resistant)*

---

## Verification Gate

### Task completion

**You:** "Add a login form to the app"

**Without Supercharger:**
> Here's the login form component I've created. It should work correctly with your authentication system. Let me know if you need any changes!

**With Supercharger:**
> Login form added to `src/components/LoginForm.tsx`. Ran `npm test` — 3/3 pass. Ran `npm run build` — clean. Handles empty fields, invalid email, and server errors. Try: `npm run dev` → `/login`.

### Bug fix

**You:** "The sidebar collapses on mobile"

**Without Supercharger:**
> I've updated the CSS to fix the sidebar. It should work now on mobile devices.

**With Supercharger:**
> Fixed `Sidebar.tsx:45` — `min-width` was `240px` (forced overflow on <768px). Changed to `min-width: 0` with flex-shrink. Tested at 320px, 375px, 768px — sidebar collapses to hamburger below 640px. `npm run build` clean.

---

## Scope Discipline

**You:** "Fix the typo in the header"

**Without Supercharger:**
> Fixed the typo. While I was there, I also refactored the header component to use a more modern pattern, updated the CSS to use Tailwind, and extracted the navigation into a separate component.

**With Supercharger:**
> Fixed 'Welcom' → 'Welcome' in `Header.tsx:12`. No other changes.
>
> (Also noticed the nav links could use `aria-label` attributes — want me to add those?)

---

## Token Economy

### Lean tier (default)

**You:** "Did the tests pass?"

**Without Supercharger:**
> I ran the test suite and I'm happy to report that all tests passed successfully. The test runner executed 57 test cases across 4 test files, and each one completed without any errors. This means our changes are working correctly and haven't introduced any regressions. Let me know if you'd like me to look at anything else!

**Lean tier:**
> Yes. 57 passed, 0 failed.

### Minimal tier

**You:** "What's the error?"

**Lean tier:**
> `TypeError: Cannot read property 'id' of undefined` at `UserService.ts:34`. The `user` object is null when `getProfile()` is called before auth completes. Add a null check.

**Minimal tier:**
> `UserService.ts:34` — null user before auth. Add guard.

### Standard tier (student-friendly)

**You:** "Why did my function return undefined?"

**Standard tier:**
> JavaScript functions return `undefined` by default when there's no explicit `return` statement. Your `calculateTotal` function has the calculation on line 8, but it's not preceded by `return`. Add `return` before the expression and it will work.

---

## Role: Developer

**You:** "How do I center a div?"

**Without Supercharger:**
> There are several ways to center a div in CSS. Let me explain the history of centering in web development, starting with the table-based layouts of the 1990s... *(500 words later)* ...here's the code.

**Developer role:**
> ```css
> .container { display: grid; place-items: center; }
> ```

**You:** "Add error handling to the API route"

**Developer role:**
> ```typescript
> app.post('/users', async (req, res) => {
>   try {
>     const user = await UserService.create(req.body);
>     res.status(201).json(user);
>   } catch (err) {
>     if (err instanceof ValidationError) return res.status(400).json({ error: err.message });
>     if (err instanceof ConflictError) return res.status(409).json({ error: 'User exists' });
>     res.status(500).json({ error: 'Internal server error' });
>   }
> });
> ```
>
> *(No explanation. No preamble. Code matches project patterns.)*

---

## Role: Writer

**You:** "Write an intro for our product launch blog post"

**Without Supercharger:**
> In today's rapidly evolving technological landscape, we are thrilled to announce the launch of our groundbreaking new product that will revolutionize the way you think about productivity...

**Writer role:**
> Before I draft, two quick questions:
> 1. Who's the audience — existing users or new prospects?
> 2. What tone — formal announcement or casual/excited?
>
> Here are 3 opening options once I know:
> - **A (Direct):** "Starting today, [Product] does X. Here's what that means for your workflow."
> - **B (Story):** "Last month, a customer asked us why X was so hard. We didn't have a good answer. Now we do."
> - **C (Data):** "Teams using [Product] ship 40% faster. Today's update makes that gap wider."

---

## Role: Student

**You:** "How do I center a div?"

**Without Supercharger:**
> ```css
> .container { display: grid; place-items: center; }
> ```

**Student role:**
> Great question! Centering is something every web developer needs. Let's build up to it.
>
> First, do you know what `display` does in CSS? It controls how an element behaves in the layout.
>
> There are three modern approaches:
>
> **1. Flexbox** (most common):
> ```css
> .parent { display: flex; justify-content: center; align-items: center; }
> ```
> `justify-content` handles horizontal, `align-items` handles vertical.
>
> **2. Grid** (simplest):
> ```css
> .parent { display: grid; place-items: center; }
> ```
> `place-items` is a shorthand for both directions at once.
>
> Try the Flexbox version in your browser. Which part makes sense? Which is confusing?

**You:** "as student: explain how git rebase works"

**Student role:**
> Imagine you're writing a book with a friend. You both started from chapter 5. Your friend finished chapters 6-7, and you wrote chapters 6-8 separately.
>
> **Merge** is like stapling both versions together with a note saying "combined here."
>
> **Rebase** is like rewriting your chapters 6-8 so they start *after* your friend's chapter 7 — as if you always had their work first.
>
> The result is the same content, but the history looks cleaner.
>
> Want to try it? Create a test repo and I'll walk you through it step by step.

---

## Role: Data

**You:** "Analyze the sales data"

**Without Supercharger:**
> Sales are increasing. Q3 was better than Q2. Revenue is up.

**Data role:**
> **Key finding:** Q3 revenue grew 23% vs Q2, driven entirely by Enterprise (+41%). SMB declined 8%.
>
> | Segment | Q2 | Q3 | Change |
> |---------|------|------|--------|
> | Enterprise | $1.2M | $1.7M | +41% |
> | SMB | $800K | $736K | -8% |
> | Total | $2.0M | $2.4M | +23% |
>
> **Assumptions:** Revenue = recognized, not booked. Currency: USD. Source: `sales_q2q3_2026.csv`.
>
> **Caveat:** SMB sample (n=47) — the -8% is not significant (p=0.12). More data needed.
>
> Query: `SELECT segment, quarter, SUM(revenue) FROM sales GROUP BY segment, quarter`

---

## Role: PM

**You:** "How long will the auth migration take?"

**Without Supercharger:**
> The auth migration should take about 2 weeks.

**PM role:**
> **Estimate (range):**
> - Optimistic: 5 days (no blockers, clean data)
> - Likely: 8 days (1-2 integration issues, testing buffer)
> - Pessimistic: 14 days (legacy edge cases, third-party changes)
>
> **Assumptions:**
> - Session tokens are well-structured (not verified)
> - OAuth providers don't require re-registration
> - No compliance review needed
>
> **Risks:**
> - [High] Legacy sessions may not migrate cleanly — suggest parallel-run
> - [Medium] OAuth callbacks need updating across 3 environments
>
> **Recommendation:** Start with a spike (1 day) to validate migration path.

---

## Clarification Mode

### Lightweight (automatic)

**You:** "Fix the app"

**Without Supercharger:**
> *(Starts reading random files, making changes based on guesses)*

**With Supercharger:**
> A few questions before I start:
> 1. Which part of the app — frontend, backend, or both?
> 2. What's the specific error or behavior you're seeing?
> 3. Any files you know are involved?

### Deep Interview

**You:** "deep interview — I want to build a dashboard"

**Without Supercharger:**
> Sure! Here's a React dashboard with charts, tables, and a sidebar navigation... *(starts building immediately)*

**With Supercharger:**
> Let me assess what we need before building.
>
> **Scoring your request:**
> - Scope: 1/3 (which pages/components?)
> - Success: 0/3 (no definition of "done")
> - Constraints: 0/3 (tech stack? existing code?)
> - Context: 1/3 (why a dashboard?)
>
> **Total: 2/12** — Full interview needed.
>
> Let's start: Who will use this dashboard — internal team, external customers, or both?

*(Continues one question at a time: data sources, update frequency, key metrics, access control. Summarizes understanding and gets explicit approval before writing code.)*

---

## Session Summary

### Manual trigger

**You:** "session summary"

**Without Supercharger:**
> We worked on some things today. Good progress!

**With Supercharger:**
> ```
> ## Session Summary — 2026-04-01
> **Working on:** Auth migration for user-service
> **Decisions made:**
> - Using refresh token rotation, 15min access token TTL
> - bcrypt 5.x had breaking change, staying on 4.x
> **Files changed:** src/auth/middleware.ts, src/auth/tokens.ts, tests/auth.test.ts
> **What was tried and failed:** bcrypt 5.x import syntax — incompatible with Node 18
> **Next steps:** Session migration script, OAuth callback updates
> **Resume with:** Continue the auth migration. Middleware and token generation
>   are done (8/8 tests passing). Next: write the session migration script in
>   src/auth/migrate-sessions.ts. Use bcrypt 4.x (not 5.x).
> ```

### After rate limit or compaction

Claude automatically generates the same summary block — so you never lose context mid-task.

### Resuming next day

```bash
$ bash tools/resume.sh

=== Latest Session Summary ===

## Session Summary — 2026-04-01
Working on: Auth migration for user-service
...

=== Resume Prompt ===

Continue the auth migration. Middleware and token generation
are done (8/8 tests passing). Next: write the session migration
script in src/auth/migrate-sessions.ts. Use bcrypt 4.x (not 5.x).

(Copied to clipboard)
```

Paste into your next Claude Code session. Full context restored.

---

## Mode Switching

Switch roles mid-conversation without reinstalling:

**You:** "as student: explain how git rebase works"

Claude shifts from code-only developer mode to teaching mode — analogies, step-by-step explanations, understanding checks.

**You:** "as developer"

Claude shifts back — code blocks only, no explanations unless asked.

**You:** "eco minimal"

Claude shifts to telegraphic output — bare deliverables, maximum token efficiency.

All switches are instant and combinable: `"as student eco standard"` = teaching mode with full sentences.

---

## Anti-Pattern Detection

The prompt validator (Full mode) catches common mistakes:

| Your prompt | Supercharger suggests |
|------------|----------------------|
| "Fix it" | Specify which files or functions to target |
| "Make it better" | Add success criteria — what does "better" mean? |
| "Build me a full app" | Break into smaller, sequential requests |
| "Fix everything and also add tests and then deploy" | Split into separate requests |
| "The thing we discussed" | Restate context — it may have been lost |
| "You already know what I mean" | Re-provide context — each session starts fresh |
| "Make it look good" | Specify visual requirements (colors, spacing, reference design) |
| "Write documentation" | Specify the audience (developers, beginners, stakeholders) |

---

## Guardrails

Always active across all roles:

1. **Read before editing** — never modify what you haven't read
2. **Stay in scope** — only change what was requested
3. **Verify before committing** — run checks, confirm output
4. **Halt when uncertain** — ask rather than guess

Risk-based autonomy:
- **Low risk** (formatting, typos) → proceeds
- **Medium risk** (new files, refactoring) → states intent first
- **High risk** (deletion, deployment) → stops and asks
