#!/usr/bin/env bash
# Claude Supercharger — Shared Secret-Detection Patterns
# Single source of truth for the SECRET_PATTERNS regex array. Sourcing this
# sets SECRET_PATTERNS in the caller's scope. Sourced by:
#   - output-secrets-scanner.sh  (scans tool OUTPUT — Bash/Read)
#   - commit-secret-guard.sh     (scans the STAGED git diff at commit)
# ONE list prevents cross-channel parity drift — a secret caught in output but
# not at commit (or vice-versa) is exactly the divergence this file exists to
# prevent. Add a pattern here and BOTH channels gain it.
# Not executable on its own — it only defines an array.

# shellcheck disable=SC2034  # consumed by the sourcing hook, not this file
SECRET_PATTERNS=(
  # AWS access-key IDs
  'AKIA[0-9A-Z]{16}'
  'ASIA[0-9A-Z]{16}'
  # AWS SECRET access-key VALUE — label + exact 40-char base64 value
  'AWS_SECRET_ACCESS_KEY.{0,6}[A-Za-z0-9/+]{40}'
  # GitHub
  'gh[opsu]_[A-Za-z0-9_]{36,}'
  # Generic key/secret/token — anchor on <keyword><:|=><16+ char value>
  '([Aa][Pp][Ii][_-]?[Kk][Ee][Yy]|[Aa][Pp][Ii][_-]?[Ss][Ee][Cc][Rr][Ee][Tt]|[Aa][Cc][Cc][Ee][Ss][Ss][_-]?[Tt][Oo][Kk][Ee][Nn])["[:space:]]{0,3}[:=][^A-Za-z0-9]{0,3}[A-Za-z0-9_/+.-]{16,}'
  'Bearer [A-Za-z0-9._-]+'
  # Private keys
  'BEGIN.{0,10}PRIVATE KEY'
  # URLs with embedded credentials
  '://[^:@/\s]+:[^@/\s]+@'
  # Stripe
  'sk_live_[0-9a-zA-Z]{24}'
  'rk_live_[0-9a-zA-Z]{24}'
  'pk_live_[0-9a-zA-Z]{24}'
  # npm
  'npm_[A-Za-z0-9]{36}'
  # JWTs
  'eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}'
  # OpenAI
  'sk-[A-Za-z0-9]{20,}'
  # Slack
  'xox[baprs]-[0-9A-Za-z-]{10,}'
  # HuggingFace
  'hf_[A-Za-z0-9]{30,}'
  # GCP service account JSON
  '"private_key":\s*"-----BEGIN'
  # GCP API key (Maps, Firebase, Translate, YouTube)
  'AIza[0-9A-Za-z_-]{35}'
  # Azure storage
  'AccountKey=[A-Za-z0-9+/]{60,}='
  # Twilio
  'SK[0-9a-f]{32}'
  # SendGrid
  'SG\.[A-Za-z0-9_-]{22,}\.[A-Za-z0-9_-]{43,}'
  # v2.9.8: crypto wallet — Ethereum/EVM private key (0x + 64 hex). The 0x prefix
  # keeps it distinct from a bare 64-hex SHA-256 checksum (lockfiles), so low FP.
  '0x[a-fA-F0-9]{64}'
)
