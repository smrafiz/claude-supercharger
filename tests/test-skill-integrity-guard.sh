#!/usr/bin/env bash
# Skill Integrity Guard — change detection for skills.
#
# skill-poisoning-scanner asks whether a skill LOOKS malicious. This asks whether
# it is the SAME FILE as last time. A skill is instructions Claude follows, so a
# silent edit is a persistent behaviour change with no event anywhere.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

echo "=== Skill Integrity Guard Tests ==="

# --- Task 1: the shared resolver -----------------------------------------------
# Two hooks must agree on which file a skill name means. One resolver, two
# consumers; two copies would drift the moment one is edited (v2.9.8).
SR_HOME=$(mktemp -d)
mkdir -p "$SR_HOME/.claude/skills/demo"
printf 'body\n' > "$SR_HOME/.claude/skills/demo/SKILL.md"

# native_path for the WRITER side of the boundary: on Git Bash python3 is native
# Windows Python and resolves an MSYS path against the current drive.
SR_HOME_N=$(native_path "$SR_HOME")

_resolve_count() {
  SR_SKILL="$1" SR_HOME_N="$SR_HOME_N" python3 -c "
import os, sys
sys.path.insert(0, sys.argv[1])
from lib_skill_resolve import resolve_skill_paths
print(len(resolve_skill_paths(os.environ['SR_SKILL'],
                              os.environ['SR_HOME_N'],
                              os.environ['SR_HOME_N'])))" "$REPO_DIR/hooks" 2>/dev/null || echo ERR
}

begin_test "resolver: finds <home>/.claude/skills/<name>/SKILL.md"
GOT=$(_resolve_count demo)
[ "$GOT" = "1" ] && pass || fail "expected 1 resolved path, got $GOT"

begin_test "resolver: a namespaced plugin:skill still resolves by bare name"
GOT=$(_resolve_count 'bundle:demo')
[ "$GOT" = "1" ] && pass || fail "namespaced name did not resolve, got $GOT"

begin_test "resolver: an unknown skill resolves to nothing"
GOT=$(_resolve_count nosuchskill)
[ "$GOT" = "0" ] && pass || fail "expected 0, got $GOT"

rm -rf "$SR_HOME"

report
