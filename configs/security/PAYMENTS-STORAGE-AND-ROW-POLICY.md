# Payments, Storage, and Row-Policy Hunting

#### When to use this file

Reach for this file when the target takes payments or grants paid entitlements, stores user uploads in object storage, or enforces access with database row policies (Postgres RLS, Supabase, Firebase rules, ORM-level tenant filters). It covers who decides that a payment happened, who chooses what is stored where, and whether a row policy constrains the row after the write as well as before it. Use `DATA-ISOLATION-AND-LIFECYCLE.md` for tenant isolation in general, `PROTOCOLS-RPC-AND-MESSAGING.md` for webhook delivery semantics, and `CLIENT-SIDE.md` for how stored content renders.

Attack classes adapted from MohammedAl-Alimi/agent-security-playbook (MIT, rules 01, 04, 06, 11, 12, 13), rewritten as stack-neutral classes. See `LICENSE-agent-security-playbook.txt`.

## Core discipline (include in every agent prompt for this domain)

```
- A payment happened only when the server learned it from the provider: a verified webhook or a server-side fetch of the session or charge. A redirect, query flag or client callback is a claim.
- Prices, currencies and quantities are server data. Follow every amount from the request to the charge call and name where it is recomputed.
- A row policy has two halves: which rows a caller may touch, and what the row may look like afterwards. Check both for every write path.
- Missing hardening is not a finding. Report a class only with a concrete path from attacker input to a wrong grant, write or read.
- Use `confirmed` for source-complete paths plus a bounded local test. Use `needs_validation` when the provider dashboard, bucket ACL or deployed policy is not in the repository.
```

## Payment and entitlement attack classes (subagent_type: `general`)

**Client-asserted payment completion**
Entitlement, credits or an order state are granted from a success redirect, a `?success=true` style flag, a client callback, or fields copied from a webhook payload, without the server verifying the signature and re-fetching paid status from the provider. Trace the grant back to its trigger.

**Client-chosen price, currency or quantity**
The request body supplies an amount, unit price, currency, raw price object or price identifier that reaches checkout or charge creation, or a quantity that is negative, fractional or unbounded. Confirm the server maps a product to an allowlisted price and recomputes every derived number.

**Grant-only entitlement lifecycle**
Cancellation, past-due, refund, dispute or failed-payment events are not handled, so access granted at purchase outlives the payment. List every event that should revoke and find its handler.

**Non-atomic balance or credit spend**
Credits, quotas or balances are checked and decremented in separate statements, so concurrent requests spend the same balance twice. Look for read-then-write without a conditional update, lock or unique constraint.

**Test and live mode confusion**
Test-mode keys, webhook secrets or price identifiers are accepted in production, or a test event can grant a live entitlement. Check how the environment selects keys and whether event mode is verified.

## Row-policy and query attack classes (subagent_type: `general`)

**Row policy re-homing**
An update policy limits which rows a caller can change but not their new values (Postgres `USING` without `WITH CHECK`, or an equivalent rule), so the caller rewrites the owner or tenant column and moves a row into another account.

**Authorization from user-writable identity metadata**
Role, tenant or plan is read from profile metadata, token claims or columns the user can edit for themselves, instead of server-controlled claims. Find who can write each field the policy reads.

**Privileged routine hijack**
A function or view runs with elevated rights (`SECURITY DEFINER`, owner-rights views, service-role clients) and either resolves names through a caller-influenced search path or returns rows the caller's own policy would hide.

**Query operator injection**
A request object reaches a NoSQL, ORM or REST filter whole, so `{"$gt": ""}`-style operators or a concatenated filter string widen the match or bypass a credential comparison. Confirm values are coerced to scalars before they reach the query.

**Dual-identifier control bypass**
A permission check resolves an object by one key (ID) while the action resolves it by another (name, slug, path), so the check and the effect can name different objects.

## Upload and storage attack classes (subagent_type: `general`)

**Upload type trusted from the declaration**
The allow decision uses the file extension or the client's Content-Type rather than the bytes, and stored SVG, HTML or polyglot files are then served inline from the application's own origin, which is stored XSS. Check the serving origin and `Content-Disposition` as well as the check.

**Client-chosen storage key**
A user-supplied filename or path becomes the object key, or an upsert on a client-influenced key overwrites another user's object. Look for traversal, collisions and missing ownership prefixes.

**Framework pre-handler gate as the only authorization**
Middleware, a layout or path-matched edge rules guard routes, but handlers, server actions or RPC endpoints reachable outside the matcher do not check again. Enumerate every entry point that reaches the same operation.
