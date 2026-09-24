Generate a DESIGN.md brand context file for this project: $ARGUMENTS

DESIGN.md is a portable design brief that future sessions auto-load when editing styles. It defines brand identity, tokens, and conventions in one place. To review an existing UI (accessibility, hierarchy, responsiveness), use `/design-review`.

Do NOT write UI code. Output only DESIGN.md.

Design sources: Google Labs' DESIGN.md format (the one Stitch uses — tokens up front, then the reasoning in a fixed section order), the W3C Design Tokens format (stable 2025), and the practice of extracting tokens from the code rather than inventing them: a brief whose colours don't match the real stylesheet makes every future edit drift.

**Step 1 — Read the tokens the project already has**
Look before asking or inventing:
- Tailwind: `tailwind.config.*` (`theme` / `extend`) or a v4 `@theme` block
- CSS custom properties in global stylesheets (`:root { --... }`)
- theme files (`theme.ts`, a MUI / Chakra / styled-components theme), SCSS variables, an existing design-tokens JSON
- the fonts actually loaded (font imports, `next/font`, `@font-face`)

Every value taken from the code is **extracted** — note where it came from. Only when nothing exists for a slot, fill it from $ARGUMENTS (a named brand or product) and mark it **proposed**. If there is no code to read and $ARGUMENTS is vague or empty, ask ONE question: "What's the brand name and primary color?"

**Step 2 — Generate DESIGN.md**

Write `DESIGN.md` to the project root. Keep it **under 4 KB** — `hooks/design-context.sh` injects at most the first 4 KB when a style file is edited, so anything past that is never seen. Omit rows the project has no value for rather than padding them.

```markdown
# DESIGN.md — [Brand Name]

## Overview
[1-2 sentences: personality, target user, visual tone]
Source: [extracted from <files> | proposed — no tokens found in code]

## Colors
| Token | Value | Role | Source |
|---|---|---|---|
| --color-primary | #... | CTA, links, focus rings | [file | proposed] |
| --color-secondary | #... | Accent, hover states | |
| --color-bg | #... | Page background | |
| --color-surface | #... | Card/panel background | |
| --color-text | #... | Body copy | |
| --color-text-muted | #... | Captions, placeholders | |
| --color-border | #... | Dividers, input borders | |
| --color-danger | #... | Errors, destructive actions | |
| --color-success | #... | Confirmations | |
Text/background pairs used for body copy must reach 4.5:1 contrast (3:1 for large text and UI components) — state the ratio of the main pair.

## Typography
| Token | Value | Usage |
|---|---|---|
| --font-sans | '...' | Body, UI |
| --font-mono | '...' | Code, data |
| --font-size-sm / base / lg / xl | ... | Captions / body / subheads / headings |
| --line-height-body | ... | Paragraphs |

## Layout & Shape
| Token | Value |
|---|---|
| --spacing-unit | ... (the scale: 4 / 8 / 12 / 16 …) |
| --radius-sm / md / lg | ... |
| breakpoints | ... |

## Elevation & Motion
- Shadows: [levels, or "none — flat"]
- Motion: [durations and easing]; respect `prefers-reduced-motion`

## Components
- [1-3 rules specific to this brand — e.g., "Always use pill buttons", "Icons: outline style only"]

## Do's and Don'ts
- Don't: [1-3 things explicitly forbidden — e.g., "No gradients on primary buttons", "Never use red outside error states"]
- Do: [the pattern to reach for instead]
```

**Step 3 — Confirm**

State: `DESIGN.md written (<N> KB). Future sessions will auto-inject this context when editing style files.` Then list which tokens were **extracted** (and from which files) and which were **proposed**, so the user knows what to check.
