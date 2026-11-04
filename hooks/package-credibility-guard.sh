#!/usr/bin/env bash
# Claude Supercharger — Package Credibility Guard
# Event: PreToolUse | Matcher: Bash,PowerShell
#
# Slopsquatting. An LLM asked for a package name that does not exist, someone
# registered it, and the install command found it waiting. 5-22% of
# LLM-suggested package names are not real, and a large share of those RECUR
# across identical prompts — that reproducibility is what makes registering them
# worth an attacker's time. The agent is the delivery mechanism, which is why
# this belongs in a harness for agents rather than in a linter.
#
# The four existing supply-chain hooks each guard a different facet and none
# guard this one: install-script-guard = lifecycle scripts, lockfile-integrity-
# guard = lockfile hashes, dep-vuln-scanner = known CVEs, package-source-guard =
# ORIGIN (non-registry sources, dependency confusion). A slopsquat has a normal
# name, comes from the REAL registry, and has no CVE because nobody has looked
# at it yet. Every one of those hooks passes it.
#
# 4.4.4: moved to PreToolUse and ASKS. The reasoning below held for the cost but
# missed the payload: a slopsquat ships its attack in an install script, which had
# already run by the time a PostToolUse warning spoke. The round-trip is paid only
# on install verbs and capped at 6s in total (package-credibility.py BUDGET_S).
# Original reasoning, kept for the record: PostToolUse, not PreToolUse. This needs a registry round-trip, and that cost is
# unacceptable BEFORE every install — the PreToolUse chain is 63-129ms today and
# a network timeout would dwarf it. dep-vuln-scanner already established this
# position: it runs `npm audit` after installs, behind the same install-verb
# gate. The install has happened by the time this speaks, which is the trade;
# the agent is still in the loop and nothing is committed.
#
# ADVISORY, never blocking, and it prints the NUMBERS rather than a verdict.
# "Registered 4 days ago, 6 downloads last week" is a fact the reader can judge;
# "suspicious package" is a claim they will disable after the second false
# positive. Thresholds are judgement calls and legitimate new packages exist.
#
# Fails open on every path it cannot complete: no curl, no network, timeout,
# unparseable response. A supply-chain check that blocks work when the registry
# is down teaches people to switch it off.
#
# Disable: SUPERCHARGER_PACKAGE_CREDIBILITY=0
set -uo pipefail
HOOKS_DIR="${BASH_SOURCE[0]%/*}"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh" 2>/dev/null || true

[ "${SUPERCHARGER_PACKAGE_CREDIBILITY:-1}" = "0" ] && exit 0

IFS= read -r -d '' -t "${SUPERCHARGER_STDIN_TIMEOUT_S:-5}" _INPUT || [ $? -le 128 ] || _INPUT=""
_INPUT="${_INPUT%"${_INPUT##*[!$'\n']}"}"

# Cheap raw-string gate before any parse — mirrors dep-vuln-scanner. Most Bash
# calls mention neither word and pay one `case` for this hook.
# v4.1.9: the short verb forms are admitted here too. This gate required the
# literal substring "install" or "add", while the install regexes below (and
# package-credibility.py:29) both list `npm i` as supported — so that
# alternative was unreachable code, and `npm i <pkg>` reached no scanner at
# all. The two-gate trap: an inner rule is dead unless the outer gate admits it.
case "$_INPUT" in *install*|*add*|*"npm i "*|*"pnpm i "*|*"yarn i "*) ;; *) exit 0 ;; esac

[ "${SUPERCHARGER_PROFILE:-standard}" = "minimal" ] && exit 0

PROJECT_DIR=$(printf '%s\n' "$_INPUT" | jq -r '.cwd // .workspace.current_dir // empty' 2>/dev/null || true)
[ -z "$PROJECT_DIR" ] && PROJECT_DIR="$PWD"
init_hook_suppress "$PROJECT_DIR" 2>/dev/null || HOOK_SUPPRESS=false

COMMAND=$(printf '%s\n' "$_INPUT" | python3 -c "
import sys, json
try:
    print(json.load(sys.stdin).get('tool_input', {}).get('command', ''))
except Exception:
    print('')
" 2>/dev/null || echo "")
[ -z "$COMMAND" ] && exit 0

command -v curl >/dev/null 2>&1 || exit 0

REPORT=$(CMD="$COMMAND" \
  SC_MIN_AGE_DAYS="${SUPERCHARGER_PKG_MIN_AGE_DAYS:-90}" \
  SC_MIN_DOWNLOADS="${SUPERCHARGER_PKG_MIN_DOWNLOADS:-1000}" \
  python3 "$HOOKS_DIR/package-credibility.py" 2>/dev/null) || REPORT=""

[ -z "$REPORT" ] && exit 0

. "$HOOKS_DIR/lib-deny.sh" 2>/dev/null || exit 0
CMD="$COMMAND"
sc_decision ask "package-credibility: ${REPORT}. A package that is very new or barely downloaded may be a slopsquat: a name an LLM invented that someone registered, with its attack in an install script that runs now." "check the repository link and publish date; if it is right, approve, or install with --ignore-scripts first."
exit 0
