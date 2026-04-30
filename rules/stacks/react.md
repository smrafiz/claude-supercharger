---
stack: react
detect:
  - package.json:react
  - "**/*.tsx"
priority: high
---

## Forbidden
- Class components in new code (use function + hooks)
- Direct DOM mutation outside refs
- setState in render path
- useEffect with empty dep array to "run once" when state is referenced
- Mutating state directly (`state.x = y`) instead of `setState({...state, x: y})`

## Toolchain
- test: vitest
- lint: eslint --fix
- typecheck: tsc --noEmit
- format: prettier --write

## Pitfalls
- useEffect deps: include every referenced state/prop or stable ref
- key prop on lists: stable id, never array index
- useState lazy init for expensive defaults: `useState(() => expensive())`
- Avoid inline object/array literals as props (breaks memoization)
- Cleanup functions in useEffect for subscriptions/timers
