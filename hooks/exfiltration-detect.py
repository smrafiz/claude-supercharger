#!/usr/bin/env python3
"""Detect data exfiltration patterns in shell commands.

Reads CMD env var. Prints a one-line reason if suspicious, else nothing.
Used by exfiltration-guard.sh.
"""
import os
import re
import sys

cmd = os.environ.get("CMD", "")

# Always-blocked: DNS tunneling tools
DNS_EXFIL_TOOLS = [
    r"\bdnscat2?\b",
    r"\biodined?\b",
    r"\bdns2tcp\b",
    r"\bdnsexfil\b",
]
for pat in DNS_EXFIL_TOOLS:
    if re.search(pat, cmd):
        print("DNS tunneling tool detected — used for covert data exfiltration")
        sys.exit(0)

# Sensitive source patterns. Match if these appear in the command.
SENSITIVE_PATHS = [
    r"\.env\b(?!\.example|\.template|\.sample|\.dist)",
    r"~/\.ssh\b|/\.ssh/",
    r"~/\.aws\b|/\.aws/",
    r"~/\.gnupg\b",
    r"/etc/shadow\b",
    r"/etc/passwd\b",
    r"/etc/sudoers\b",
    r"\.pem\b",
    r"id_rsa\b|id_ed25519\b|id_ecdsa\b",
    r"\.kube/config\b",
    r"\.npmrc\b",
    r"\.pgpass\b",
    r"credentials\b",
]

# Cloud upload commands
CLOUD_UPLOADS = [
    (r"\baws\s+s3\s+(cp|mv|sync)\b", "aws s3 upload"),
    (r"\bgsutil\s+(cp|mv|rsync)\b", "gsutil upload"),
    (r"\baz\s+storage\s+(blob|file)\s+upload\b", "az storage upload"),
    (r"\bazcopy\s+copy\b", "azcopy upload"),
    (r"\brclone\s+(copy|sync|move)\b", "rclone upload"),
    (r"\bs3cmd\s+put\b", "s3cmd upload"),
]

for upload_re, label in CLOUD_UPLOADS:
    if not re.search(upload_re, cmd):
        continue
    for sens in SENSITIVE_PATHS:
        if re.search(sens, cmd):
            print(f"{label} of sensitive source — possible credential/key exfiltration")
            sys.exit(0)

# curl/wget POST/upload of sensitive files
NETWORK_UPLOADS = [
    r"\bcurl\b.*(?:--data-binary|--upload-file|-F\s|--form\b|-d\s)",
    r"\bwget\b.*--post-file=",
    r"\bnc\b.*(?:-c|<|<<)",
    r"\bnetcat\b.*(?:-c|<|<<)",
]
for upload_re in NETWORK_UPLOADS:
    if not re.search(upload_re, cmd):
        continue
    for sens in SENSITIVE_PATHS:
        if re.search(sens, cmd):
            print(f"network upload of sensitive source — possible credential exfiltration")
            sys.exit(0)
