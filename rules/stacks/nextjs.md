---
stack: nextjs
detect:
  - package.json:next
  - next.config.js
  - next.config.mjs
  - next.config.ts
priority: high
---

## Forbidden
- "use client" in components that don't actually need browser APIs
- fetch in client components when server component can fetch
- Manual route handlers when API routes suffice
- Importing server-only utilities (db client, secrets) into client components
- next/router in app dir (use next/navigation)

## Toolchain
- dev: next dev
- build: next build
- test: vitest
- lint: next lint

## Pitfalls
- Server components default — only opt into client with "use client"
- async server components are valid; async client components are not
- Metadata exports must be in server components
- Static images: use next/image (not <img>) for layout shift prevention
- env vars: NEXT_PUBLIC_ prefix exposes to client; everything else is server-only
