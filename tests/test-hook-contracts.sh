#!/usr/bin/env bash
# Hook contract meta-tests (v2.26.59)
#
# From a full-project consistency audit. These assert properties EVERY hook must
# hold, rather than testing any one hook — the gaps they close were invisible to
# 200 per-hook test files because each file only ever looked at its own hook.
#
# Deliberately NOT included: a refactor of the 58 hooks that emit deny JSON via
# inline printf into a shared helper. That was the tidy fix and the wrong one —
# it touches every security hook's deny path at once, and this project rejected
# merging guards for the same reason (isolation is why several bugs this week
# were survivable). The JSON-validity test below buys most of the safety at a
# fraction of the risk.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

echo "=== Hook Contract Tests ==="

# --- 1. every kill-switch is documented --------------------------------------
# 31 of 49 hooks had an env kill-switch with nothing in the header naming it, so
# the escape hatch for elicitation-guard, env-exec-guard, bulk-exfil-guard and
# 28 others existed but was discoverable only by reading the source.
begin_test "contract: every env kill-switch is named in its hook's header"
MISS=""
for f in "$REPO_DIR"/hooks/*.sh; do
  grep -qE '\[ "\$\{SUPERCHARGER_[A-Z_]+:-1\}" = "0" \]' "$f" || continue
  # 'Disable:' anywhere in the header block — some hooks write it mid-sentence
  # ("Fully fail-open. Disable: X=0"), which an anchored ^# Disable: match misses.
  # That mis-detection made my first pass duplicate a line in claim-evidence-gate.
  head -40 "$f" | grep -q 'Disable:' || MISS="$MISS $(basename "$f")"
done
[ -z "$MISS" ] && pass || fail "undocumented kill-switch in:$MISS"

begin_test "contract: the documented switch is the one the hook actually reads"
# A header naming the wrong variable is worse than none — the user sets it,
# nothing happens, and the guard looks broken rather than mis-documented.
BAD=""
for f in "$REPO_DIR"/hooks/*.sh; do
  used=$(grep -m1 -oE '\$\{SUPERCHARGER_[A-Z_]+:-1\}' "$f" 2>/dev/null | grep -oE 'SUPERCHARGER_[A-Z_]+') || continue
  [ -z "$used" ] && continue
  head -40 "$f" | grep -q "$used" || BAD="$BAD $(basename "$f")($used)"
done
[ -z "$BAD" ] && pass || fail "header names a different var than the code reads:$BAD"

# --- 2. every file in hooks/ declares its role --------------------------------
# hooks/ mixes registered hooks with shared helpers (cmd-normalize, statusline…).
# Nothing distinguished them, so 4 files "missing" an Event header and 2 absent
# from HOOKS.md looked like drift when they were correct.
begin_test "contract: every hooks/*.sh declares either an Event or a Helper role"
UND=""
for f in "$REPO_DIR"/hooks/*.sh; do
  case "$(basename "$f")" in lib-*|lib_*) continue ;; esac
  head -8 "$f" | grep -qE '^# (Event|Events|Helper):' || UND="$UND $(basename "$f")"
done
[ -z "$UND" ] && pass || fail "no Event:/Helper: declaration in:$UND"

begin_test "contract: files marked Helper are not registered as hooks"
BAD=""
for f in "$REPO_DIR"/hooks/*.sh; do
  head -8 "$f" | grep -q '^# Helper:' || continue
  b=$(basename "$f")
  grep -q "hooks_dir}/$b" "$REPO_DIR/lib/hooks.sh" && BAD="$BAD $b"
done
[ -z "$BAD" ] && pass || fail "marked Helper but registered in lib/hooks.sh:$BAD"

# --- 3. deny output must be valid JSON ---------------------------------------
# 58 hooks hand-roll their deny payload with inline printf. Claude Code discards
# the ENTIRE output of a hook whose JSON is malformed, so a quoting slip turns a
# block into a silent allow. Hit exactly this class in the subagent chain, where
# a report containing raw quotes could have corrupted the emission.
#
# Drives each hook that can deny with a payload designed to trip it, and parses
# whatever it prints. Hooks that decline to fire simply print nothing — also fine.
begin_test "contract: every hook that emits a permission decision emits valid JSON"
BAD=$(python3 - "$REPO_DIR" <<'PY'
import json, os, subprocess, sys, tempfile, pathlib

repo = pathlib.Path(sys.argv[1])
# A payload carrying hostile-but-plausible content in the fields hooks read:
# unbalanced quotes, a backslash, a newline, and a brace — the shapes that break
# hand-rolled JSON.
hostile = 'rm -rf / "unclosed \\ brace} \n second line'
payloads = [
    {"tool_name": "Bash", "tool_input": {"command": hostile}, "cwd": "."},
    {"tool_name": "Write", "tool_input": {"file_path": "/etc/passwd", "content": hostile}, "cwd": "."},
    {"tool_name": "Edit", "tool_input": {"file_path": hostile}, "cwd": "."},
]
bad = []
for h in sorted((repo / 'hooks').glob('*.sh')):
    if h.name.startswith(('lib-', 'lib_')):
        continue
    head = '\n'.join(h.read_text(errors='replace').split('\n')[:8])
    if head.startswith('#') and '# Helper:' in head:
        continue
    for p in payloads:
        with tempfile.TemporaryDirectory() as st:
            os.makedirs(os.path.join(st, 'scope'), exist_ok=True)
            try:
                r = subprocess.run(['bash', str(h)], input=json.dumps(p),
                                   capture_output=True, text=True, timeout=20,
                                   env=dict(os.environ, SUPERCHARGER_STATE=st,
                                            SUPERCHARGER_NO_NOTIFY='1'))
            except Exception:
                continue
        out = (r.stdout or '').strip()
        if not out:
            continue
        # A hook may print several JSON objects, one per line.
        for line in out.split('\n'):
            line = line.strip()
            if not line or not line.startswith('{'):
                continue
            try:
                json.loads(line)
            except Exception as e:
                bad.append(f"{h.name}: {e}")
                break
        if bad and bad[-1].startswith(h.name):
            break
print('; '.join(bad))
PY
)
[ -z "$BAD" ] && pass || fail "malformed JSON (Claude Code discards the whole payload): $BAD"

# --- 4. events the docs called dead are alive and registered ------------------
# docs/HOOK_AUTHORING.md said MessageDisplay and UserPromptExpansion "were later
# dropped — current CC rejects them as unknown events", and that our hooks for
# them were removed in v2.7.25. Both statements went stale: the events are in
# Claude Code's current documented list, and the hooks were re-added afterwards.
#
# The risk was never a crash — it was a maintainer reading that note and deleting
# display-secret-redactor, which its own tests call the only guard protecting the
# HUMAN (it redacts secrets from what gets rendered). Prose rots; this does not.
begin_test "contract: MessageDisplay is registered (the human-facing secret guard)"
grep -qE 'hooks\+=\("MessageDisplay\|' "$REPO_DIR/lib/hooks.sh" && pass \
  || fail "display-secret-redactor lost its registration — nothing redacts secrets from rendered output"

begin_test "contract: UserPromptExpansion is registered (slash-command body scan)"
grep -qE 'hooks\+=\("UserPromptExpansion\|' "$REPO_DIR/lib/hooks.sh" && pass \
  || fail "expanded slash-command bodies are no longer scanned for injection"

begin_test "contract: the authoring doc no longer calls those events invalid"
# The exact sentence that invited the deletion.
grep -q 'current CC rejects them as unknown events' "$REPO_DIR/docs/HOOK_AUTHORING.md" \
  && fail "the stale note is back — it tells maintainers two live hooks are dead" || pass

report
