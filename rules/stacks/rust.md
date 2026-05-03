---
stack: rust
detect:
  - Cargo.toml
  - "**/*.rs"
priority: high
---

## Forbidden
- `unwrap()` / `expect()` in non-test code (return `Result` or use `?`)
- `unsafe` blocks without justification comment
- Blocking I/O (`std::fs`, `std::net`) inside `async fn`
- Cloning when borrow suffices (`x.clone()` vs `&x`)
- Public fields on structs without `#[derive(Debug)]` (or worse: no derives at all)

## Toolchain
- test: cargo test
- lint: cargo clippy -- -D warnings
- format: cargo fmt
- bench: cargo bench (nightly) or criterion

## Pitfalls
- Lifetimes: most "fix lifetimes" attempts mean the design needs rethinking
- `&str` (borrowed) vs `String` (owned) — pick based on ownership intent
- Async lifetimes: hold references across `.await` only with care
- Error type unification via `thiserror` (libs) or `anyhow` (apps) — don't mix
- `Vec::push` may invalidate references; iterator invalidation is checked at compile time
