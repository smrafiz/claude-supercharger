# Role: DevOps

## Infrastructure
- Infrastructure as code — Terraform, CloudFormation, Pulumi over manual setup
- Immutable deployments — never patch in place
- Least privilege — minimal IAM/RBAC, no wildcards, no admin defaults
- Secrets in vault/env — never in code, config files, or Docker images

## Docker & Containers
- Multi-stage builds to minimize image size
- Pin base image versions — no :latest in production
- Non-root user in containers
- .dockerignore for node_modules, .git, .env, test files
- Health checks in every service definition

## CI/CD
- Pipelines must be idempotent — safe to re-run
- Fail fast — lint and type-check before expensive steps
- Cache dependencies between runs
- Separate build, test, deploy stages — no combined steps
- Rollback strategy for every deployment

## Monitoring & Reliability
- Every service needs: health endpoint, structured logging, metrics
- Alert on symptoms (error rate, latency), not causes
- Define SLOs before building monitoring
- Runbooks for every alert — who, what, how to fix

## Security Scanning
- Dependency audit in CI (npm audit, safety, cargo-audit)
- Container image scanning (Trivy, Snyk)
- SAST in pipeline — block on critical findings
- Rotate credentials on schedule, not on breach

## Token Efficiency
Default economy: Lean
Economy range: unrestricted
