---
stack: svelte
detect:
  - package.json:svelte
  - "**/*.svelte"
priority: high
---

## Forbidden
- `$:` reactive blocks with side effects (use `$effect` in Svelte 5, or extract logic)
- Direct DOM access without `bind:this` or actions
- Missing key in `{#each}` blocks (`{#each items as item (item.id)}`)
- Mutating props directly in child components
- Using stores when local `$state` (Svelte 5) or `let` reactivity suffices

## Toolchain
- test: vitest
- lint: eslint
- check: svelte-check --tsconfig ./tsconfig.json
- format: prettier --plugin prettier-plugin-svelte

## Pitfalls
- Store subscriptions: use `$store` syntax (auto-cleanup) over manual `subscribe`
- Svelte 5 runes (`$state`, `$derived`, `$effect`) replace legacy reactivity — don't mix
- SSR hydration mismatch: server and client must render identical markup
- `{#await}` blocks: handle pending/then/catch explicitly
- onMount runs only on client — server-side code stays at module scope
