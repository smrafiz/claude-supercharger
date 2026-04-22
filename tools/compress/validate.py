#!/usr/bin/env python3
"""Validate compressed markdown preserves critical content from original."""

import re
from pathlib import Path

URL_REGEX = re.compile(r"https?://[^\s)]+")
FENCE_OPEN_REGEX = re.compile(r"^(\s{0,3})(`{3,}|~{3,})(.*)$")
HEADING_REGEX = re.compile(r"^(#{1,6})\s+(.*)", re.MULTILINE)
BULLET_REGEX = re.compile(r"^\s*[-*+]\s+", re.MULTILINE)
PATH_REGEX = re.compile(
    r"(?:\./|\.\./|/|[A-Za-z]:\\)[\w\-/\\\.]+|[\w\-\.]+[/\\][\w\-/\\\.]+")


class ValidationResult:
    def __init__(self):
        self.is_valid = True
        self.errors: list[str] = []
        self.warnings: list[str] = []

    def add_error(self, msg: str):
        self.is_valid = False
        self.errors.append(msg)

    def add_warning(self, msg: str):
        self.warnings.append(msg)


def extract_headings(text: str):
    return [(level, title.strip()) for level, title in HEADING_REGEX.findall(text)]


def extract_code_blocks(text: str) -> list[str]:
    """Line-based fenced code block extractor. Handles nested fences."""
    blocks = []
    lines = text.split("\n")
    i, n = 0, len(lines)
    while i < n:
        m = FENCE_OPEN_REGEX.match(lines[i])
        if not m:
            i += 1
            continue
        fence_char = m.group(2)[0]
        fence_len = len(m.group(2))
        block_lines = [lines[i]]
        i += 1
        closed = False
        while i < n:
            close_m = FENCE_OPEN_REGEX.match(lines[i])
            if (close_m
                    and close_m.group(2)[0] == fence_char
                    and len(close_m.group(2)) >= fence_len
                    and close_m.group(3).strip() == ""):
                block_lines.append(lines[i])
                closed = True
                i += 1
                break
            block_lines.append(lines[i])
            i += 1
        if closed:
            blocks.append("\n".join(block_lines))
    return blocks


def extract_urls(text: str) -> set[str]:
    return set(URL_REGEX.findall(text))


def extract_paths(text: str) -> set[str]:
    return set(PATH_REGEX.findall(text))


def count_bullets(text: str) -> int:
    return len(BULLET_REGEX.findall(text))


def validate_headings(orig: str, comp: str, result: ValidationResult):
    h1 = extract_headings(orig)
    h2 = extract_headings(comp)
    if len(h1) != len(h2):
        result.add_error(f"Heading count mismatch: {len(h1)} → {len(h2)}")
    if h1 != h2:
        result.add_warning("Heading text/order changed")


def validate_code_blocks(orig: str, comp: str, result: ValidationResult):
    c1 = extract_code_blocks(orig)
    c2 = extract_code_blocks(comp)
    if c1 != c2:
        result.add_error("Code blocks not preserved exactly")


def validate_urls(orig: str, comp: str, result: ValidationResult):
    u1 = extract_urls(orig)
    u2 = extract_urls(comp)
    if u1 != u2:
        result.add_error(f"URL mismatch: lost={u1 - u2}, added={u2 - u1}")


def validate_paths(orig: str, comp: str, result: ValidationResult):
    p1 = extract_paths(orig)
    p2 = extract_paths(comp)
    if p1 != p2:
        result.add_warning(f"Path mismatch: lost={p1 - p2}, added={p2 - p1}")


def validate_bullets(orig: str, comp: str, result: ValidationResult):
    b1 = count_bullets(orig)
    b2 = count_bullets(comp)
    if b1 == 0:
        return
    diff = abs(b1 - b2) / b1
    if diff > 0.15:
        result.add_warning(f"Bullet count drift: {b1} → {b2} ({diff:.0%})")


def validate(original_path: Path, compressed_path: Path) -> ValidationResult:
    result = ValidationResult()
    orig = original_path.read_text(errors="ignore")
    comp = compressed_path.read_text(errors="ignore")

    validate_headings(orig, comp, result)
    validate_code_blocks(orig, comp, result)
    validate_urls(orig, comp, result)
    validate_paths(orig, comp, result)
    validate_bullets(orig, comp, result)

    return result


if __name__ == "__main__":
    import sys
    if len(sys.argv) != 3:
        print("Usage: python validate.py <original> <compressed>")
        sys.exit(1)

    orig = Path(sys.argv[1]).resolve()
    comp = Path(sys.argv[2]).resolve()
    res = validate(orig, comp)

    print(f"\nValid: {res.is_valid}")
    if res.errors:
        print("\nErrors:")
        for e in res.errors:
            print(f"  - {e}")
    if res.warnings:
        print("\nWarnings:")
        for w in res.warnings:
            print(f"  - {w}")
