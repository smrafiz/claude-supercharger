#!/usr/bin/env bash
# Claude Supercharger — Critical-infra path matcher (single source of truth)
# Sourced by BOTH critical-infra-guard.sh (to force a confirm on the edit) and
# lib-smart-approve.sh (to refuse auto-approval so autopilot can't swallow the
# confirm). Keeping the pattern list in ONE place means the two callers can never
# drift — the sibling-parity bug class this project has hit before.
#
# Operationalizes guardrails.md's documented "Human review triggers: stop before
# modifying CI/CD, changing auth logic, touching DB schemas". Those are advisory
# prose the model may ignore; this turns four of them into an unbypassable gate.
#
# is_critical_infra_path "<file_path>"  → exit 0 (matched) and echoes the category
#                                          name on stdout; exit 1 (no match), no output.
# Conservative on purpose: a false positive nags the user (the exact thing that
# drives churn), so match by path SEGMENT / distinctive filename, never a bare
# substring like "auth" that would fire on author.js.

_sc_ci_match() {
  # Normalize: basename for filename tests, lowercased whole path for dir-segment tests.
  local p="$1"
  [ -z "$p" ] && return 1
  # Windows tools pass C:\repo\.github\workflows\ci.yml; no */segment/* glob sees a backslash.
  p="${p//\\//}"
  local base="${p##*/}"
  local lower
  lower=$(printf '%s' "$p" | tr '[:upper:]' '[:lower:]')
  # The dir-segment arms below matched on $lower while every FILENAME arm matched
  # on $base in its original case, so `DOCKERFILE` fell through while `Dockerfile`
  # and `dockerfile` were caught — the same file on APFS/NTFS, which are
  # case-insensitive by default. Fold once here and let every filename arm compare
  # $lbase against lowercase literals: an arm cannot drift from a spelling it never
  # states ([[one-path-many-spellings]]).
  local lbase="${lower##*/}"
  # Normalize a relative path to a leading segment so */segment/* globs also match
  # at the path root (".github/workflows/ci.yml" → "./.github/workflows/ci.yml").
  case "$lower" in /*) ;; *) lower="./$lower" ;; esac

  # 1. CI/CD pipelines
  case "$lower" in
    */.github/workflows/*|*/.gitlab-ci.yml|.gitlab-ci.yml|*/.circleci/*|\
    */azure-pipelines.yml|azure-pipelines.yml|*/.travis.yml|.travis.yml|\
    */bitbucket-pipelines.yml|bitbucket-pipelines.yml|*/.drone.yml|.drone.yml)
      echo "CI/CD pipeline"; return 0 ;;
  esac
  case "$lbase" in
    jenkinsfile) echo "CI/CD pipeline"; return 0 ;;
    # v4.2.0: CODEOWNERS decides whose review a change needs; editing it can route
    # review away from the people who must approve (root, .github/ or docs/).
    codeowners) echo "code-owner review rules (CODEOWNERS)"; return 0 ;;
  esac

  # 2. Container / infra-as-code deploy
  case "$lbase" in
    dockerfile|dockerfile.*|containerfile) echo "container/deploy"; return 0 ;;
    docker-compose.yml|docker-compose.yaml|docker-compose.*.yml|compose.yml|compose.yaml)
      echo "container/deploy"; return 0 ;;
    *.tf|*.tfvars) echo "infrastructure-as-code"; return 0 ;;
    # Overwriting state orphans every resource it tracks (applygate delta, 2026-11-10).
    *.tfstate|*.tfstate.backup) echo "Terraform state"; return 0 ;;
  esac

  # 3. DB schema / migrations
  case "$lower" in
    */migrations/*|*/migrate/*|*/alembic/versions/*|*/db/migrate/*)
      echo "DB migration/schema"; return 0 ;;
  esac
  case "$lbase" in
    schema.prisma) echo "DB migration/schema"; return 0 ;;
  esac

  # 4. Auth / authorization logic (segment-matched to avoid author.js false hits)
  case "$lower" in
    */auth/*|*/authentication/*|*/authorization/*|*/middleware/auth*|*/guards/auth*)
      echo "auth logic"; return 0 ;;
  esac
  case "$lbase" in
    passport.js|passport.ts|*.strategy.js|*.strategy.ts) echo "auth logic"; return 0 ;;
  esac

  return 1
}

# SymJack: Write/Edit follow a symlink (verified on CC 2.1.327), so a decoy
# `notes.txt -> .github/workflows/ci.yml` lands on the pipeline while every
# string match above sees "notes.txt". Judge the resolved target too.
is_critical_infra_path() {
  _sc_ci_match "$1" && return 0
  local r c
  r=$(_sc_ci_resolve "$1") || return 1
  [ "$r" != "$1" ] || return 1
  c=$(_sc_ci_match "$r") || return 1
  echo "$c (via symlink to $r)"
}

# Builtin tests only, no fork: true when the path or any parent is a symlink.
_sc_ci_has_link() {
  local d="$1"
  while [ -n "$d" ]; do
    [ -L "$d" ] && return 0
    case "$d" in */*) d="${d%/*}" ;; *) return 1 ;; esac
  done
  return 1
}

# Real location of a path that crosses a symlink, even if the file itself does
# not exist yet. Fails (rc 1) when no component is a link.
_sc_ci_resolve() {
  local p="$1" t d i=0
  _sc_ci_has_link "$p" || return 1
  while [ -L "$p" ] && [ "$i" -lt 40 ]; do
    t=$(readlink "$p") || return 1
    case "$t" in /*) p="$t" ;; *) case "$p" in */*) p="${p%/*}/$t" ;; *) p="$t" ;; esac ;; esac
    i=$((i + 1))
  done
  case "$p" in */*) d="${p%/*}"; [ -n "$d" ] || d=/ ;; *) d=. ;; esac
  d=$(cd -P "$d" 2>/dev/null && pwd) || { printf '%s\n' "$p"; return 0; }
  printf '%s/%s\n' "${d%/}" "${p##*/}"
}
