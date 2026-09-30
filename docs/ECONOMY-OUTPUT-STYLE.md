# Output style vs the economy tiers: measurement

Moved out of `configs/universal/economy.md` (v4.1.24): it loaded into every session
as an instruction, but it is evidence for humans.

This file governs what a response **contains**. The strongest available control over
how **long** it is, is Claude Code's output style — a style rewrites the system
prompt, while this file is delivered as a user message after it.

Measured on the Supercharger repo itself: one session, split at the exact moment
`/output-style concise` was run, with the minimal tier active and reinforced every
turn on **both** sides of the split. Assistant prose characters per turn, tool-only
turns excluded.

| window   | before (median / mean) | after (median / mean) | median cut |
|----------|------------------------|-----------------------|------------|
| ±60 min  | 278 / 652              | 144 / 466             | 48%        |
| ±90 min  | 278 / 652              | 152 / 448             | 45%        |
| ±120 min | 278 / 652              | 152 / 432             | 45%        |

n = 38 before, 33–39 after. The whole-session split reads 55%, but that number is
inflated by task mix — the earlier window was research and report writing. The tight
windows are the honest figure.

So if responses still run longer than the active tier promises, the fix is not
another rule in this file. Run:

    /output-style concise

Claude Code saves that choice to `.claude/settings.local.json` — **per-project and
per-machine.** It does not travel with the repo, and Supercharger does not install
it. Set it once on each machine you work from.
