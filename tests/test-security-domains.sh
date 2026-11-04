#!/usr/bin/env bash
# /sc-security domain attack-class files (configs/security/, Cloudflare
# security-audit-skill, MIT): the command, the installer and the plugin copy must
# all agree on which files exist and where they live, or a family agent reads
# nothing and COVERAGE claims a domain it never loaded.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

CMD="$REPO_DIR/configs/commands/sc-security.md"
PLUGIN_CMD="$REPO_DIR/commands/security.md"
SEC="$REPO_DIR/configs/security"
echo "=== /sc-security Domain File Tests ==="

begin_test "every domain file the command names ships in configs/security/"
# Count first: with no names and no folder, both loops below run zero times and pass.
NAMED=$(grep -oE '`[A-Z][A-Z-]+\.md`' "$CMD" | sort -u | wc -l | tr -d ' ')
MISSING=""
[ "$NAMED" -ge 11 ] || MISSING=" (only $NAMED named, expected all 11)"
for f in $(grep -oE '`[A-Z][A-Z-]+\.md`' "$CMD" | tr -d '`' | sort -u); do
  [ -f "$SEC/$f" ] || MISSING="$MISSING $f"
done
[ -z "$MISSING" ] && pass || fail "named by sc-security.md but not shipped:$MISSING"

begin_test "every shipped domain file is named by the command (no orphan never read)"
SHIPPED=$(ls "$SEC"/*.md 2>/dev/null | wc -l | tr -d ' ')
ORPHAN=""
[ "$SHIPPED" -ge 11 ] || ORPHAN=" (only $SHIPPED shipped, expected 11)"
for p in "$SEC"/*.md; do
  f=$(basename "$p")
  grep -q "\`$f\`" "$CMD" || ORPHAN="$ORPHAN $f"
done
[ -z "$ORPHAN" ] && pass || fail "shipped but never assigned to a family:$ORPHAN"

begin_test "domain files cross-reference only files that ship"
BAD=""
[ -f "$SEC/ATTACK-CLASSES.md" ] || BAD=" (configs/security/ missing)"
for f in $(grep -ohE '[A-Z][A-Z-]+\.md' "$SEC"/*.md | sort -u); do
  [ -f "$SEC/$f" ] || BAD="$BAD $f"
done
[ -z "$BAD" ] && pass || fail "a domain file points at a file that is not shipped:$BAD"

begin_test "the MIT notice for the copied Cloudflare text ships with it"
grep -q 'Copyright (c) .* Cloudflare' "$SEC/LICENSE-cloudflare.txt" 2>/dev/null \
  && grep -q 'Permission is hereby granted' "$SEC/LICENSE-cloudflare.txt" && pass \
  || fail "LICENSE-cloudflare.txt missing or not the MIT text"

begin_test "plugin copy reads the domain files from the plugin root, where they exist"
# Installer: ~/.claude/supercharger/security/. Plugin: the repo is the root, so
# the same files sit at configs/security/ there.
grep -q '${CLAUDE_PLUGIN_ROOT}/configs/security/' "$PLUGIN_CMD" \
  && ! grep -q 'supercharger/security' "$PLUGIN_CMD" && pass \
  || fail "commands/security.md does not point at \${CLAUDE_PLUGIN_ROOT}/configs/security/"

begin_test "denial of service is reportable in deep only, and only against a shared resource"
EXCL=$(grep -m1 '^\*\*Hard exclusions' "$CMD")
F7=$(grep -m1 '^| F7 ' "$CMD")
{ printf '%s' "$EXCL" | grep -q 'except under F7 in `deep`' \
  && printf '%s' "$EXCL" | grep -q 'shared with other principals' \
  && printf '%s' "$F7" | grep -q '(`deep` only)'; } && pass \
  || fail "DoS exclusion lost its deep-only, shared-resource carve-out"

begin_test "a fact the repo cannot show becomes NEEDS VALIDATION, with no severity"
grep -q '^NEEDS VALIDATION (no severity' "$CMD" \
  && grep -q 'Unresolved fact:' "$CMD" \
  && grep -q '`needs_validation` with that fact named' "$CMD" && pass \
  || fail "needs_validation verdict or its report section is missing"

begin_test "deep keeps ONE saved report per repository, so vulnerability details do not pile up"
# A dated name per run accumulated a file of findings every run, never deleted.
grep -q 'audit/security/<repo>\.md' "$CMD" \
  && ! grep -qE 'audit/security/<repo>-' "$CMD" && pass \
  || fail "the deep report path is not a single per-repo file"

begin_test "installer deploys the domain files and their licence"
setup_test_home
# shellcheck source=lib/hooks.sh
( source "$REPO_DIR/lib/utils.sh" 2>/dev/null; source "$REPO_DIR/lib/hooks.sh"; deploy_hook_scripts "$REPO_DIR" ) >/dev/null 2>&1
GOT=$(ls "$HOME/.claude/supercharger/security" 2>/dev/null | sort | tr '\n' ' ')
WANT=$(ls "$SEC" | sort | tr '\n' ' ')
[ -n "$WANT" ] && [ "$GOT" = "$WANT" ] && pass || fail "deployed [$GOT], expected [$WANT]"
teardown_test_home

report
