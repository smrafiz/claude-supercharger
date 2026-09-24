Review the UI for accessibility, hierarchy and responsiveness: $ARGUMENTS

Read-only: this produces a report, it changes no files. To create a design brief, use `/design`.

Design sources: WCAG 2.2 (W3C WAI — the current standard, adding focus-not-obscured, target size and dragging alternatives at AA), Deque's measurement that automated tools find only a minority of accessibility issues, Nielsen's usability heuristics, and the OneRedOak design-review workflow (look at the rendered UI first, three viewports, severity triage, describe the problem rather than prescribe the fix).

**Rule: numbers, not adjectives.** "Low contrast" is not a finding; "#8a8a8a on #ffffff is 3.4:1, below the 4.5:1 needed for body text" is. Every finding names the element (selector, component or `file:line`) and the measured value.

**Step 0 — Scope**
$ARGUMENTS names routes, pages or components. If empty, review the UI files in the current branch's diff (`git diff --name-only` against the default branch).

**Step 1 — Look at the rendered UI when you can**
If a browser tool is available (Playwright MCP, Claude in Chrome) and the app runs locally, open each page and capture it at **1440, 768 and 375 px** wide. Walk the main flow with the keyboard only. Read the browser console for errors. If no browser or running app is available, review the code only, and say so in the report — some findings then cannot be confirmed.

**Step 2 — Accessibility: WCAG 2.2 AA**
- **Contrast** — compute the ratio for each text/background pair from the actual colour values: 4.5:1 for normal text, 3:1 for large text and for UI components and focus indicators.
- **Keyboard** — everything reachable and operable by keyboard, in a sensible order; no traps.
- **Focus** — visible on every interactive element, and not hidden behind sticky headers, banners or overlays (2.4.11).
- **Target size** — at least 24×24 CSS px, or enough spacing (2.5.8).
- **Dragging** — any drag interaction has a single-pointer alternative (2.5.7).
- **Names and labels** — every input has a label, every icon-only button an accessible name, every meaningful image alt text; semantic elements (`button`, `nav`, headings in order) rather than `div`s with click handlers.
- **Reflow and resize** — usable at 320 px wide without horizontal scrolling, and with text at 200%.
- **Motion** — animation respects `prefers-reduced-motion`.
- **Forms** — errors identified in text, not only by colour; no re-entering the same information (3.3.7).

Run axe-core or Lighthouse **only if already installed** in the project — never download them. Report what they found as one input, not a verdict.

**Step 3 — Hierarchy and usability**
One clear primary action per view; visual weight matching importance; consistent spacing and alignment; states that exist and make sense (loading, empty, error, disabled, hover, active); destructive actions confirmed; copy that tells the user what happened and what to do next. Judge against Nielsen's heuristics — visibility of status, match with the real world, consistency, error prevention, recognition over recall.

**Step 4 — Responsiveness**
At each viewport: no horizontal scroll, no overlapping or clipped content, tap targets reachable, navigation usable, images and tables contained.

**Step 5 — Design-system consistency**
If `DESIGN.md` or a token source exists (Tailwind theme, CSS custom properties, a theme file), flag one-off values that bypass it: hard-coded colours, spacing off the scale, ad-hoc font sizes. Each is a `file:line`.

**Output format:**
```
DESIGN REVIEW: [scope] · rendered: [yes — 1440/768/375 | no — code only]

BLOCKERS (prevent use, or fail WCAG A/AA on a main flow):
- [element — file:line] — [measured value vs requirement] — [who it affects]

HIGH:
- ...
MEDIUM:
- ...
NITS:
- ...

CONSISTENCY: [off-token values — file:line]
CONSOLE: [errors | clean | not checked]

NOT COVERED: automated and code-level checks find only part of accessibility
problems. Screen-reader testing and testing with users are still needed for
[the flows reviewed].
```

Describe each problem and its impact; suggest the direction of a fix only where it is not obvious. If nothing fails, say so plainly — do not pad the report.
