Generate a DESIGN.md brand context file for this project: $ARGUMENTS

DESIGN.md is a portable design brief that future sessions auto-load when editing styles. It defines brand identity, tokens, and conventions in one place.

Do NOT write UI code. Output only DESIGN.md.

**Step 1 — Gather brand context**

If $ARGUMENTS names a known brand or product, infer colors/typography from that identity.
If $ARGUMENTS is vague or empty, ask ONE question: "What's the brand name and primary color?"

**Step 2 — Generate DESIGN.md**

Write `DESIGN.md` to the project root with this structure:

```markdown
# DESIGN.md — [Brand Name]

## Brand Identity
[1-2 sentences: personality, target user, visual tone]

## Color Tokens
| Token | Hex | Usage |
|---|---|---|
| --color-primary | #... | CTA, links, focus rings |
| --color-secondary | #... | Accent, hover states |
| --color-bg | #... | Page background |
| --color-surface | #... | Card/panel background |
| --color-text | #... | Body copy |
| --color-text-muted | #... | Captions, placeholders |
| --color-border | #... | Dividers, input borders |
| --color-danger | #... | Errors, destructive actions |
| --color-success | #... | Confirmations |

## Typography
| Token | Value | Usage |
|---|---|---|
| --font-sans | '...' | Body, UI |
| --font-mono | '...' | Code, data |
| --font-size-base | 16px | Base |
| --font-size-sm | 14px | Labels, captions |
| --font-size-lg | 20px | Subheadings |
| --font-size-xl | 28px | Headings |
| --line-height-body | 1.6 | Paragraphs |

## Spacing & Shape
| Token | Value |
|---|---|
| --radius-sm | 4px |
| --radius-md | 8px |
| --radius-lg | 16px |
| --spacing-unit | 8px |

## Component Conventions
- [1-3 bullet rules specific to this brand — e.g., "Always use pill buttons", "No drop shadows", "Icons: outline style only"]

## Anti-Patterns
- [1-3 things explicitly forbidden — e.g., "No gradients on primary buttons", "Never use red outside error states"]
```

**Step 3 — Confirm**

State: `DESIGN.md written. Future sessions will auto-inject this context when editing style files.`
