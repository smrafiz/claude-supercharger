#!/usr/bin/env bash
# Claude Supercharger — Guard Registration Check
# Event: SessionStart | Matcher: (none)
#
# Verifies that Supercharger's hooks are actually REGISTERED, because an install
# that silently stops registering is indistinguishable from a working one — and
# the session is told the opposite. Measured before writing this: with an empty
# hooks key in settings.json, every SessionStart hook stayed silent except
# project-config, which announced "Claude Supercharger is active. Guardrails are
# on — I will not make destructive changes without asking." A false assurance is
# worse than no assurance.
#
# setup-check.sh already performs this validation correctly and thoroughly, but
# it is registered on the `Setup` event, which fires only for `--init`,
# `--init-only` and `--maintenance`. A normal session never triggers it, so the
# one check that would catch this never ran in ordinary use. It is also 96ms
# (measured, 10 runs) — too expensive to bolt onto SessionStart, which already
# runs a dozen hooks. Hence a separate, deliberately minimal check rather than
# re-registering that one.
#
# Three independent projects hit this same class in one week: a hook chain
# bricked by a vanished symlink target, a plugin whose guards silently never
# installed in a cloud session, and this repo's own install sitting four
# releases behind with three shipped guards inactive and nothing saying so.
# The shared shape is protection believed present and actually absent.
#
# Behaviour: warn only, never blocks. Fail-open on every unreadable path — a
# check that cannot read its evidence must not claim a verdict.
# Disable: SUPERCHARGER_GUARD_REG_CHECK=0

set -euo pipefail

HOOKS_DIR="${BASH_SOURCE[0]%/*}"
# shellcheck source=hooks/lib-timing.sh
. "$HOOKS_DIR/lib-timing.sh" 2>/dev/null || true

[ "${SUPERCHARGER_GUARD_REG_CHECK:-1}" = "0" ] && exit 0

# Drain stdin so the parent never takes SIGPIPE on the payload.
cat >/dev/null 2>&1 || true

# PLUGIN RUNTIME: Claude Code sets CLAUDE_PLUGIN_ROOT only when it loaded us as
# a plugin, which means it registered our hooks from the plugin's own
# hooks.json — there is no user settings.json entry to look for, and checking
# for one would cry wolf at exactly the users who are fully protected. This is
# the plugin/installer path divergence that has produced silent no-ops here
# before, so the discriminator is checked FIRST and exits before any file read.
[ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && exit 0

SETTINGS="$HOME/.claude/settings.json"

# Fail open, not closed: an unreadable settings.json is not evidence of a
# missing install, and warning on it would train the user to ignore this.
[ -r "$SETTINGS" ] || exit 0

# Fork-free: a single builtin read plus a case test. Every registered hook
# command carries the `#supercharger` tag appended at generation time, so its
# presence anywhere in the file is sufficient proof that registration happened.
# This is the whole steady-state cost of the check.
_GRC_BODY=$(<"$SETTINGS") || exit 0
case "$_GRC_BODY" in
  *'#supercharger'*)
    # Tagged entries exist, so registration happened at some point. That is NOT
    # the same as "all of it is still there": on 2026-08-30 a /sc on restored 154
    # registrations of which 59 came back in a shape Claude Code ignores, and this
    # check stayed silent because the surviving 95 still carried the tag. Measured
    # at the time: 1-of-154 registered was silent, and so was a tagged hook whose
    # file did not exist. Presence is a proxy; the defect is partial loss.
    #
    # install.sh stamps the count it left behind, so compare against that. No
    # stamp -> fail open to the old presence behaviour rather than guess a floor.
    _GRC_STAMP="$HOME/.claude/supercharger/.registration-count"
    [ -r "$_GRC_STAMP" ] || exit 0
    read -r _GRC_WANT < "$_GRC_STAMP" 2>/dev/null || exit 0
    case "$_GRC_WANT" in ''|*[!0-9]*) exit 0 ;; esac
    [ "$_GRC_WANT" -gt 0 ] || exit 0

    # Occurrences, not lines: sc-toggle rewrites this file and a reformat that put
    # two tags on one line would make `grep -c` undercount and cry wolf. The stamp
    # is written with this same expression, so the two are always the same metric.
    _GRC_HAVE=$(grep -o -- '#supercharger' "$SETTINGS" 2>/dev/null | wc -l | tr -d ' ')
    case "$_GRC_HAVE" in ''|*[!0-9]*) exit 0 ;; esac
    [ "$_GRC_HAVE" -ge "$_GRC_WANT" ] && exit 0

    printf '{"systemMessage":"[Supercharger] PARTIAL PROTECTION. %s of %s registrations are present in ~/.claude/settings.json — the rest are gone, so those guards are not running. A /sc off followed by /sc on before v4.0.0 could restore entries in a shape Claude Code ignores. Fix: bash ~/.claude/supercharger/tools/update.sh --yes  (or re-run install.sh). Silence: SUPERCHARGER_GUARD_REG_CHECK=0"}\n' \
      "$_GRC_HAVE" "$_GRC_WANT"
    exit 0
    ;;
esac

# Not registered. Say so once, plainly, and name the fix. Deliberately a
# systemMessage rather than stderr: a hook's stderr lands in the debug log as an
# unhandled line, while stdout JSON is parsed and shown to the user — verified
# against a live build when version-floor-check was written.
printf '{"systemMessage":"[Supercharger] NOT PROTECTING THIS SESSION. No Supercharger hooks are registered in ~/.claude/settings.json, so no guard is running: destructive commands, credential leaks and path violations are all unguarded right now. This usually means an interrupted install or update. Fix: bash ~/.claude/supercharger/tools/update.sh --yes  (or re-run install.sh). Silence: SUPERCHARGER_GUARD_REG_CHECK=0"}\n'

exit 0
