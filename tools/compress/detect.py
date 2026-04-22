#!/usr/bin/env python3
"""Detect whether a file is natural language (compressible) or code/config (skip)."""

import json
import re
from pathlib import Path

COMPRESSIBLE_EXTENSIONS = {".md", ".txt", ".markdown", ".rst"}

SKIP_EXTENSIONS = {
    ".py", ".js", ".ts", ".tsx", ".jsx", ".json", ".yaml", ".yml",
    ".toml", ".env", ".lock", ".css", ".scss", ".html", ".xml",
    ".sql", ".sh", ".bash", ".zsh", ".go", ".rs", ".java", ".c",
    ".cpp", ".h", ".hpp", ".rb", ".php", ".swift", ".kt", ".lua",
    ".dockerfile", ".makefile", ".csv", ".ini", ".cfg",
}

# Sensitive file denylist — refuse before reading content.
# Compression sends raw bytes to the API — never ship credentials.
SENSITIVE_BASENAME_REGEX = re.compile(
    r"(?ix)^("
    r"\.env(\..+)?"
    r"|\.netrc"
    r"|credentials(\..+)?"
    r"|secrets?(\..+)?"
    r"|passwords?(\..+)?"
    r"|id_(rsa|dsa|ecdsa|ed25519)(\.pub)?"
    r"|authorized_keys"
    r"|known_hosts"
    r"|.*\.(pem|key|p12|pfx|crt|cer|jks|keystore|asc|gpg)"
    r")$"
)

SENSITIVE_PATH_COMPONENTS = frozenset({".ssh", ".aws", ".gnupg", ".kube", ".docker"})

SENSITIVE_NAME_TOKENS = (
    "secret", "credential", "password", "passwd",
    "apikey", "accesskey", "token", "privatekey",
)

CODE_PATTERNS = [
    re.compile(r"^\s*(import |from .+ import |require\(|const |let |var )"),
    re.compile(r"^\s*(def |class |function |async function |export )"),
    re.compile(r"^\s*(if\s*\(|for\s*\(|while\s*\(|switch\s*\(|try\s*\{)"),
    re.compile(r"^\s*[\}\]\);]+\s*$"),
    re.compile(r"^\s*@\w+"),
    re.compile(r'^\s*"[^"]+"\s*:\s*'),
    re.compile(r"^\s*\w+\s*=\s*[{\[\(\"']"),
]


def is_sensitive_path(filepath: Path) -> bool:
    """Heuristic denylist for files that must never be sent to a third-party API."""
    name = filepath.name
    if SENSITIVE_BASENAME_REGEX.match(name):
        return True
    lowered_parts = {p.lower() for p in filepath.parts}
    if lowered_parts & SENSITIVE_PATH_COMPONENTS:
        return True
    lower = re.sub(r"[_\-\s.]", "", name.lower())
    return any(tok in lower for tok in SENSITIVE_NAME_TOKENS)


def _is_code_line(line: str) -> bool:
    return any(p.match(line) for p in CODE_PATTERNS)


def _is_json_content(text: str) -> bool:
    try:
        json.loads(text)
        return True
    except (json.JSONDecodeError, ValueError):
        return False


def _is_yaml_content(lines: list[str]) -> bool:
    yaml_indicators = 0
    for line in lines[:30]:
        stripped = line.strip()
        if stripped.startswith("---"):
            yaml_indicators += 1
        elif re.match(r"^\w[\w\s]*:\s", stripped):
            yaml_indicators += 1
        elif stripped.startswith("- ") and ":" in stripped:
            yaml_indicators += 1
    non_empty = sum(1 for line in lines[:30] if line.strip())
    return non_empty > 0 and yaml_indicators / non_empty > 0.6


def detect_file_type(filepath: Path) -> str:
    """Classify as 'natural_language', 'code', 'config', or 'unknown'."""
    ext = filepath.suffix.lower()

    if ext in COMPRESSIBLE_EXTENSIONS:
        return "natural_language"
    if ext in SKIP_EXTENSIONS:
        return "config" if ext in {".json", ".yaml", ".yml", ".toml", ".ini", ".cfg", ".env"} else "code"

    # Extensionless files — check content
    if not ext:
        try:
            text = filepath.read_text(errors="ignore")
        except (OSError, PermissionError):
            return "unknown"

        lines = text.splitlines()[:50]
        if _is_json_content(text[:10000]):
            return "config"
        if _is_yaml_content(lines):
            return "config"

        code_lines = sum(1 for line in lines if line.strip() and _is_code_line(line))
        non_empty = sum(1 for line in lines if line.strip())
        if non_empty > 0 and code_lines / non_empty > 0.4:
            return "code"

        return "natural_language"

    return "unknown"


def should_compress(filepath: Path) -> bool:
    """Return True if the file is natural language and safe to compress."""
    if not filepath.is_file():
        return False
    if filepath.name.endswith(".original.md"):
        return False
    return detect_file_type(filepath) == "natural_language"


if __name__ == "__main__":
    import sys
    if len(sys.argv) < 2:
        print("Usage: python detect.py <file1> [file2] ...")
        sys.exit(1)
    for path_str in sys.argv[1:]:
        p = Path(path_str).resolve()
        file_type = detect_file_type(p)
        compress = should_compress(p)
        sensitive = is_sensitive_path(p)
        print(f"  {p.name:30s} type={file_type:20s} compress={compress}  sensitive={sensitive}")
