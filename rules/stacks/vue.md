---
stack: vue
detect:
  - package.json:vue
  - "**/*.vue"
priority: high
---

## Forbidden
- Options API in new code (Composition API + `<script setup>`)
- Mutating `reactive()` state from outside its owner
- `v-html` with user-supplied or untrusted data
- Direct prop mutation in child components
- `watch` with `immediate: true` when `watchEffect` fits

## Toolchain
- test: vitest
- lint: eslint --ext .vue,.ts
- typecheck: vue-tsc --noEmit
- format: prettier --write

## Pitfalls
- `ref` for primitives, `reactive` for objects — picking wrong one breaks reactivity
- Computed values cache by deps; mutating internals doesn't invalidate
- Refs auto-unwrap in templates but not in `<script>`
- `defineProps` and `defineEmits` are compile-time macros — no import needed
- v-for keys: stable id, never index, never object reference
