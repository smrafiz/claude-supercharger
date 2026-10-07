Dead code and unused-import removal for: $ARGUMENTS

Two-tier safety model. Auto-fix only what a compiler or linter has **proven** unused inside one file (**Tier 1**). Everything else needs explicit approval (**Tier 2**). When in doubt, keep the code: a missed deletion costs nothing, a wrong one breaks production.

Design sources: Meta's SCARF automated dead-code removal (tool evidence plus a repo-wide text search before any delete; accept false negatives over false positives), Google's large-scale changes (small batches, each tested on its own), Fowler's *Remove Dead Code* (version control is the safety net), and the documented false-positive behaviour of knip, ruff, Vulture, staticcheck, Go `deadcode`, cargo-machete / cargo-udeps, psalm and depcheck.

## Rules for the whole run

- **Tools: only if already installed**, always in report mode. Look in `node_modules/.bin`, the virtualenv, `PATH` and the project's scripts. Never `npx` / `pipx run` / `uvx` a tool that isn't there — that downloads and executes code. Never let a tool apply its own `--fix`: you make every edit, so each one is reviewable.
- **Respect exemptions the repo already wrote**: `knip.json` ignores, ruff config, a Vulture whitelist, `@psalm-api`, `# noqa`, entry-point config.
- **"Looks unused" is not evidence.** Every removal cites a tool finding or a compiler warning.

## Step 1 — Recon

- Languages and frameworks in scope.
- **Is this a library?** A published package (`exports` / `main` in `package.json`, `__all__`, `pub` items, a crate or gem others depend on) — then exported symbols are its API, not dead code.
- Installed tools, from this table:

| Stack | Proven in-file (Tier 1 source) | Graph / heuristic (Tier 2 leads only) |
|---|---|---|
| JS/TS | `tsc --noEmit --noUnusedLocals --noUnusedParameters`, eslint `no-unused-vars` | knip (files, exports, deps, members), ts-unused-exports, depcheck |
| Python | ruff `F841` (unused local) | ruff `F401` (imports — ruff itself marks this fix unsafe), Vulture (any confidence), `ERA001` (commented-out code) |
| Go | compiler (unused imports/locals fail the build) | staticcheck `U1000` (never flags exported), `deadcode ./...` (whole-program, functions only, blind to reflection) |
| Rust | `cargo check` `unused_*` warnings | cargo-machete (regex, imprecise), cargo-udeps (accurate, needs nightly) |
| PHP | — | `psalm --find-dead-code` |
| Java/Kotlin | compiler / IDE unused-local | IDE "unused declaration", UCDetector (blind to reflection and DI unless entry points are set) |

## Step 2 — Collect candidates (read-only)

Run each installed tool in report mode. Record per candidate: tool, finding, confidence, and tier.

## Step 3 — False-positive checklist

Run every check that applies. **Any yes moves the item to Tier 2**, or out of the list entirely:

1. **Text search** — the bare name, across the whole repo, including non-code: templates, SQL, shell scripts, Makefiles, CI YAML, JSON/YAML config, docs and examples. Any hit means it is used.
2. **Dynamic use** — `getattr`, `eval`, reflection, `import()` / `require()` with a computed path, registries, string-keyed dispatch tables.
3. **Framework convention** — a route or page file (Next.js `pages/`, `app/`), Django `urls` / `admin` / `signals` / migrations, Rails conventions, Spring or DI beans, controllers, plugin entry points.
4. **Side-effect import** — an import with no bindings: `import './register'`, CSS or asset imports, polyfills, Python modules imported to register something, Rust `#[used]`. **Never auto-remove these.**
5. **Serialization / ORM** — a field read by name by an ORM, serializer, schema or DI container.
6. **Public API** — exported from a library (Step 1). Propose deprecation, never deletion.
7. **Type-only use** — used only in type annotations; some tools miss this.
8. **Generated code** — a codegen header or build-output path. Fix the generator, not its output.
9. **Recent history** — `git log -S<name>` shows it was added recently, or its callers were deleted recently: it may be half-finished work or behind a feature flag.
10. **Test-only** — referenced only from tests. Delete both or neither — approval.

## Tier 1 — auto-fix (proven, in-file)

Apply without asking, only when a compiler or linter flags it inside one file **and** it passes the checklist:

- Unused local variables
- Unused imports **that bind a name** (never side-effect imports)
- Duplicate consecutive imports
- Unreachable code after `return`, `throw`, `process.exit`, `panic`, `os.Exit`

Process: one batch per category → build, type-check and run the tests → **one commit per category**, naming the tool that found it. Any failure: restore that batch, halt, report.

## Tier 2 — require approval (per item, never in bulk)

- Exported functions, classes or types with zero callers in this repo
- Symbols used only in tests
- Files that look orphaned
- Dynamic-dispatch suspects
- Commented-out code blocks (flagged by `ERA001` or by reading; `git blame` age is context, not proof)
- Functions never called and empty
- **Dependencies** — unused-dependency tools miss use in config files (babel, eslint, vite), dynamic `require` and re-exports. Check config files and the lockfile before proposing.

For each approved item: delete → build, type-check, test → commit → restore on failure.

**If nothing fails when you delete it, that does not prove it was dead.** It may only prove nothing tests it. Say so in the report.

## Output format

```
RECON: [languages / frameworks] · library: [yes — public API protected | no] · tools: [installed] · not installed (grep fallback): [...]

=== Tier 1: Applied ===
- [file:line] removed unused [import | local | unreachable code]: [name] — [tool]
Commits: [sha per category] · build / types / tests: [pass | FAILED — batch restored]

=== Tier 2: Awaiting approval ===
1. [symbol] @ [file:line]
   - Found by: [tool, confidence]
   - Text search: [no other hits | hits in: ...]
   - Last touched: [date, commit]
   - Checklist: [clear | flagged: rule N]
   - Risk if removed: [public API break / hidden dynamic call / test removal]
2. ...

DEPRECATE INSTEAD (public API): [symbol — suggested notice]
KEPT (checklist hit): [symbol — rule]
NO TEST COVERED: [symbols whose removal broke nothing]

Reply with the numbers you want removed (e.g., "1, 3") or "skip all".
```

If no findings, say so plainly. Do not pad with marginal items.
