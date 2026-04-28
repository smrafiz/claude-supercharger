#!/usr/bin/env bash
# Claude Supercharger — PreCompact Priority Preservation
# Event: PreCompact | Matcher: (none)
# Augments the default compact prompt with fidelity rules so the
# summarizer preserves high-signal context (root causes, exact numbers,
# unanswered questions, subagent findings, file:line refs, A-vs-B
# decisions). Output is appended to the default 9-section compact prompt
# under "Additional Instructions:".
#
# Inspired by fcakyon/claude-codex-settings/intelligent-compact (Apache-2.0).

set -uo pipefail
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh"

# Drain stdin (PreCompact may pass JSON; we don't need it).
cat >/dev/null 2>&1 || true

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
init_hook_suppress "$PROJECT_DIR"
check_hook_disabled "precompact-priorities" && exit 0
hook_profile_skip "precompact-priorities" && exit 0

cat << 'PRIORITY_BLOCK'
<priority-preservation-instructions>
These requirements augment the 9 required sections. They do not replace
any section — they raise the fidelity bar for content categories that
the default prompt leaves under-specified.

A. UNANSWERED QUESTIONS
   For each user message, mark it as answered, partially answered, or
   unanswered. Add a "Pending Questions" sub-heading and list every
   unanswered or partially answered user question verbatim.

B. ROOT CAUSES, NOT SYMPTOMS
   Distinguish confirmed root causes from ruled-out hypotheses. Record
   every confirmed root cause with its file path and line number
   (pattern: `path/to/file.py:42`). Keep ruled-out hypotheses so they
   don't get re-tried. Never paraphrase an error message, error code,
   or stack frame — preserve them verbatim.

C. EXACT NUMBERS AND IDS
   Preserve exact digits everywhere they appear: benchmark results,
   profiling output, error rates, latencies, token counts, costs, PR
   numbers, issue numbers, commit SHAs, run IDs, dataset names, and
   model IDs. Never round, never paraphrase a quantitative value.

D. FILE PATH IMPORTANCE TIERS
   Group files by importance: critical (caused or fixed the issue),
   referenced (read for context), mentioned (appeared in discussion
   only). Use the pattern `path/to/file.py:42` whenever a specific
   line matters.

E. SUBAGENT FINDINGS ARE PRIMARY EVIDENCE
   For every Task/Agent tool result in the transcript, preserve the
   agent's final report in full — file paths, code references,
   citations, and quantitative findings. Subagent runs are expensive
   to redo; treat their reports as primary evidence, not as
   compressible chatter.

F. A-VS-B COMPARISONS
   When alternatives were under evaluation (tool X vs tool Y, approach
   1 vs approach 2), preserve both sides and the decision criteria.
   If a decision was reached, record which side won and the reasoning.

G. SUPERCHARGER STATE
   Preserve: active economy tier (lean/standard/minimal), active role
   (developer/writer/etc.), current performance profile (standard/
   fast/minimal), disabled hooks list, project-level
   .supercharger.json contents.

Priority when cutting for length: if A-G would otherwise be dropped to
fit, drop conversational filler, repeated tool output, and intermediate
reasoning first.
</priority-preservation-instructions>
PRIORITY_BLOCK

exit 0
