#!/usr/bin/env python3
"""
Supercharger Memory Compression

Compresses natural language files (CLAUDE.md, MEMORY.md, todos, preferences)
into terse format to reduce input tokens. Preserves all technical substance,
code blocks, URLs, paths, and markdown structure.

Usage:
    python compress.py <filepath>

Adapted from caveman-compress with Supercharger economy tier rules.
"""

import os
import re
import subprocess
import sys
from pathlib import Path

from .detect import should_compress, is_sensitive_path
from .validate import validate

MAX_RETRIES = 2
MAX_FILE_SIZE = 500_000  # 500KB

OUTER_FENCE_REGEX = re.compile(
    r"\A\s*(`{3,}|~{3,})[^\n]*\n(.*)\n\1\s*\Z", re.DOTALL
)


def strip_llm_wrapper(text: str) -> str:
    """Strip outer ```markdown ... ``` fence when it wraps the entire output."""
    m = OUTER_FENCE_REGEX.match(text)
    return m.group(2) if m else text


def call_claude(prompt: str) -> str:
    """Call Claude via API key or CLI fallback."""
    api_key = os.environ.get("ANTHROPIC_API_KEY")
    if api_key:
        try:
            import anthropic
            client = anthropic.Anthropic(api_key=api_key)
            msg = client.messages.create(
                model=os.environ.get("SUPERCHARGER_MODEL", "claude-sonnet-4-5"),
                max_tokens=8192,
                messages=[{"role": "user", "content": prompt}],
            )
            return strip_llm_wrapper(msg.content[0].text.strip())
        except ImportError:
            pass

    # Fallback: claude CLI
    try:
        result = subprocess.run(
            ["claude", "--print"],
            input=prompt,
            text=True,
            capture_output=True,
            check=True,
        )
        return strip_llm_wrapper(result.stdout.strip())
    except subprocess.CalledProcessError as e:
        raise RuntimeError(f"Claude call failed:\n{e.stderr}")


def build_compress_prompt(original: str) -> str:
    return f"""Compress this markdown to reduce tokens while preserving all technical substance.

RULES:
- Remove: articles (a/an/the), filler (just/really/basically), pleasantries, hedging
- Remove: "in order to" → "to", "make sure to" → "ensure", connective fluff (however/furthermore)
- Use: fragments, short synonyms (big not extensive, fix not "implement a solution for")
- Drop: "you should", "remember to" — state the action directly
- Merge redundant bullets that say the same thing differently

NEVER MODIFY:
- Code blocks (``` ... ```) — copy EXACTLY
- Inline code (`backticks`) — preserve EXACTLY
- URLs, file paths, commands, technical terms, proper nouns
- Dates, version numbers, environment variables
- Markdown headings (keep exact text, compress body below)
- Bullet hierarchy and numbering
- Table structure (compress cell text, keep structure)
- YAML frontmatter

Return ONLY the compressed markdown. No outer fence wrapper.

TEXT:
{original}
"""


def build_fix_prompt(original: str, compressed: str, errors: list[str]) -> str:
    errors_str = "\n".join(f"- {e}" for e in errors)
    return f"""Fix specific validation errors in this compressed markdown.

DO NOT recompress. ONLY fix listed errors. Leave everything else as-is.

ERRORS:
{errors_str}

FIX INSTRUCTIONS:
- Missing URL: restore from ORIGINAL exactly where it belongs
- Code block mismatch: restore exact code block from ORIGINAL
- Heading mismatch: restore exact heading text from ORIGINAL

ORIGINAL (reference):
{original}

COMPRESSED (fix this):
{compressed}

Return ONLY the fixed file. No explanation.
"""


def compress_file(filepath: Path) -> bool:
    filepath = filepath.resolve()

    if not filepath.exists():
        raise FileNotFoundError(f"File not found: {filepath}")
    if filepath.stat().st_size > MAX_FILE_SIZE:
        raise ValueError(f"File too large (max 500KB): {filepath}")
    if is_sensitive_path(filepath):
        raise ValueError(
            f"Refusing to compress {filepath}: filename matches sensitive pattern "
            "(credentials, keys, secrets). Compression sends content to API. "
            "Rename if false positive."
        )

    print(f"Processing: {filepath}")

    if not should_compress(filepath):
        print("Skipping (not natural language)")
        return False

    original_text = filepath.read_text(errors="ignore")
    backup_path = filepath.with_name(filepath.stem + ".original.md")

    if backup_path.exists():
        print(f"Backup already exists: {backup_path}")
        print("Aborting to prevent data loss. Remove/rename backup to proceed.")
        return False

    # Compress
    print("Compressing...")
    compressed = call_claude(build_compress_prompt(original_text))

    # Write backup + compressed
    backup_path.write_text(original_text)
    filepath.write_text(compressed)

    # Validate + retry
    for attempt in range(MAX_RETRIES):
        print(f"\nValidation attempt {attempt + 1}")
        result = validate(backup_path, filepath)

        if result.is_valid:
            # Report savings
            orig_size = len(original_text.encode("utf-8"))
            comp_size = len(compressed.encode("utf-8"))
            savings = (1 - comp_size / orig_size) * 100 if orig_size > 0 else 0
            print(f"Validation passed. Savings: {savings:.0f}% ({orig_size} → {comp_size} bytes)")
            if result.warnings:
                for w in result.warnings:
                    print(f"  Warning: {w}")
            return True

        print("Validation failed:")
        for err in result.errors:
            print(f"  - {err}")

        if attempt == MAX_RETRIES - 1:
            # Restore original
            filepath.write_text(original_text)
            backup_path.unlink(missing_ok=True)
            print("Failed after retries — original restored")
            return False

        print("Attempting targeted fix...")
        compressed = call_claude(
            build_fix_prompt(original_text, compressed, result.errors)
        )
        filepath.write_text(compressed)

    return False


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python compress.py <filepath>")
        sys.exit(1)

    target = Path(sys.argv[1]).resolve()
    success = compress_file(target)
    sys.exit(0 if success else 1)
