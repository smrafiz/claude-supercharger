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

is_critical_infra_path() {
  # Normalize: basename for filename tests, lowercased whole path for dir-segment tests.
  local p="$1"
  [ -z "$p" ] && return 1
  local base="${p##*/}"
  local lower
  lower=$(printf '%s' "$p" | tr '[:upper:]' '[:lower:]')
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
  case "$base" in
    Jenkinsfile|jenkinsfile) echo "CI/CD pipeline"; return 0 ;;
  esac

  # 2. Container / infra-as-code deploy
  case "$base" in
    Dockerfile|dockerfile|Dockerfile.*|Containerfile) echo "container/deploy"; return 0 ;;
    docker-compose.yml|docker-compose.yaml|docker-compose.*.yml|compose.yml|compose.yaml)
      echo "container/deploy"; return 0 ;;
    *.tf|*.tfvars) echo "infrastructure-as-code"; return 0 ;;
  esac

  # 3. DB schema / migrations
  case "$lower" in
    */migrations/*|*/migrate/*|*/alembic/versions/*|*/db/migrate/*)
      echo "DB migration/schema"; return 0 ;;
  esac
  case "$base" in
    schema.prisma) echo "DB migration/schema"; return 0 ;;
  esac

  # 4. Auth / authorization logic (segment-matched to avoid author.js false hits)
  case "$lower" in
    */auth/*|*/authentication/*|*/authorization/*|*/middleware/auth*|*/guards/auth*)
      echo "auth logic"; return 0 ;;
  esac
  case "$base" in
    passport.js|passport.ts|*.strategy.js|*.strategy.ts) echo "auth logic"; return 0 ;;
  esac

  return 1
}
