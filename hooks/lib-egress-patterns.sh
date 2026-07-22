#!/usr/bin/env bash
# Claude Supercharger — Shared egress classification patterns (Python regex source)
# The two egress guards — webfetch-egress-guard.sh (WebFetch url) and
# mcp-egress-guard.sh (MCP tool args) — are the cross-channel-parity pair. Keeping
# their block/warn regexes HERE (one source, inherited by each guard's python via
# the environment) stops them drifting; review found real drift — a stray paste
# entry in one, and both missed Discord's versioned API path + alternate IMDS-IP
# encodings + a userinfo-@ private-net bypass.
#
# These are PYTHON regex strings (re.search). Exported so the `python3 -c` child
# inherits them via os.environ. Callers source this before invoking python.

# Cloud instance-metadata (credential-theft SSRF). Dotted-quad + decimal + hex +
# IPv6 encodings of 169.254.169.254, plus the ECS/GCP/Azure metadata path tokens
# (which catch the realistic GET forms regardless of how the host is written).
# v2.22.5: added Alibaba IMDS (100.100.100.200), the IPv6 hextet spelling of
# 169.254.169.254 (a9fe:a9fe), and octal/hex-dotted + octal-dword encodings that
# curl/libcurl/browsers resolve to the IMDS v4 address. (Guards percent-decode
# the blob first — 2.22.5 — so encoded path tokens like /latest/%6d… are caught.)
EGRESS_METADATA_RE='169\.254\.169\.254|2852039166|0xa9fea9fe|a9fe:a9fe|100\.100\.100\.200|025177724776|0251\.0376\.0251\.0376|0xa9\.0xfe\.0xa9\.0xfe|\[?fd00:ec2::254\]?|metadata\.google\.internal|169\.254\.170\.2|/latest/meta-data/|computemetadata/v1|/metadata/instance'

# Chat webhooks (exfil channels). Discord supports a versioned path
# (/api/v10/webhooks/…) as well as the bare /api/webhooks/… form.
# v2.22.5: Slack Workflow-Builder inbound webhooks use /triggers/ and /workflows/
# (not just /services); plus Telegram Bot API and webhook.site/requestbin/pipedream
# — all one-request exfil channels.
EGRESS_WEBHOOK_RE='discord(app)?\.com/api/(v[0-9]+/)?webhooks|hooks\.slack\.com/(services|triggers|workflows)|outlook\.office\.com/webhook|webhook\.office\.com|api\.telegram\.org/bot[0-9]|webhook\.site|requestbin\.|\.pipedream\.net'

# Paste / anonymous-transfer sites (exfil endpoints).
EGRESS_PASTE_RE='\b(pastebin\.com|paste\.rs|paste\.ee|hastebin\.com|dpaste\.|ix\.io|0x0\.st|transfer\.sh|file\.io|termbin\.com|gofile\.io|anonfiles|catbox\.moe|rentry\.co|controlc\.com|bashupload\.com|tmpfiles\.org)'

# Private-network / loopback (SSRF into internal services) — advisory WARN. Allows
# an optional userinfo (user@host) prefix so `http://user@10.0.0.5/…` is still caught.
EGRESS_PRIVATE_RE='https?://([^/@ ]*@)?(127\.[0-9]+\.[0-9]+\.[0-9]+|localhost|10\.[0-9]+\.[0-9]+\.[0-9]+|192\.168\.[0-9]+\.[0-9]+|172\.(1[6-9]|2[0-9]|3[01])\.[0-9]+\.[0-9]+|\[::1\]|0\.0\.0\.0)'

export EGRESS_METADATA_RE EGRESS_WEBHOOK_RE EGRESS_PASTE_RE EGRESS_PRIVATE_RE
