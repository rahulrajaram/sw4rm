#!/usr/bin/env python3
from __future__ import annotations

import os
import re
import sys
from typing import Iterator, Tuple


DOCS_ROOT = "documentation"


def iter_markdown_files(root: str) -> Iterator[str]:
    for dirpath, _, filenames in os.walk(root):
        for fn in sorted(filenames):
            if fn.endswith(".md"):
                yield os.path.join(dirpath, fn)


def check_docs() -> int:
    rc = 0
    numbered_bad_style: list[Tuple[str, int, str]] = []
    missing_blank_before_ordered: list[Tuple[str, int, str]] = []
    missing_blank_before_unordered: list[Tuple[str, int, str]] = []
    inline_commands: list[Tuple[str, int, str]] = []

    ordered_re = re.compile(r"^\s*\d+\.\s")
    ordered_paren_re = re.compile(r"^\s*\d+\)\s")
    unordered_re = re.compile(r"^\s*[-*+]\s")
    heading_re = re.compile(r"^\s*#{1,6}\s")
    blockquote_re = re.compile(r"^\s*>")
    admonition_re = re.compile(r"^\s*!{3}\s")
    html_re = re.compile(r"^\s*<")

    inline_code_re = re.compile(r"`([^`]+)`")
    inline_cmd_prefix = re.compile(
        r"^(brew|apt|apt-get|docker|grpcurl|sw4rm-doctor|make|python3|python\s+-m|pip|kubectl|twine|mkdocs|virtualenv|git|go|newgrp|usermod)\b"
    )

    for path in iter_markdown_files(DOCS_ROOT):
        with open(path, "r", encoding="utf-8") as fh:
            lines = fh.read().splitlines()

        # Precompute which lines are inside fenced code blocks
        in_fence_flags = [False] * len(lines)
        in_fence = False
        fence_delim = None
        for i, line in enumerate(lines):
            if line.strip().startswith("```") or line.strip().startswith("~~~"):
                token = line.strip()[:3]
                if not in_fence:
                    in_fence = True
                    fence_delim = token
                elif token == fence_delim:
                    in_fence = False
                    fence_delim = None
                in_fence_flags[i] = True
                continue
            if in_fence:
                in_fence_flags[i] = True

        def prev_visible_index(idx: int) -> int | None:
            j = idx - 1
            while j >= 0:
                s = lines[j].strip()
                if in_fence_flags[j] or s == "" or s.startswith("```") or s.startswith("~~~"):
                    j -= 1
                    continue
                return j
            return None

        for i, line in enumerate(lines):
            if in_fence_flags[i]:
                continue

            # 1) style check (should be 1.)
            if ordered_paren_re.match(line):
                numbered_bad_style.append((path, i + 1, line))

            # Spacing rule: require a blank line before the first list item
            if ordered_re.match(line) or unordered_re.match(line):
                prev_immediate = lines[i - 1] if i > 0 else ""
                s = prev_immediate.strip()
                # OK if immediate previous line is blank or part of a continuing list or fence marker
                ok = (
                    s == ""
                    or ordered_re.match(prev_immediate) is not None
                    or unordered_re.match(prev_immediate) is not None
                    or s.startswith("```")
                    or s.startswith("~~~")
                )
                if not ok:
                    if ordered_re.match(line):
                        missing_blank_before_ordered.append((path, i + 1, line))
                    else:
                        missing_blank_before_unordered.append((path, i + 1, line))

            # Inline command detection: inline code that looks like a shell command
            # Skip inline-command check on list bullets to reduce false positives in explanatory bullets
            if unordered_re.match(line) or ordered_re.match(line):
                pass
            else:
                for m in inline_code_re.finditer(line):
                    content = m.group(1).strip()
                    # Ignore markdown snippets like [Link](path) shown inline
                    if "[" in content and ")" in content:
                        continue
                    # Command prefixes
                    is_cmd = False
                    if content == "sw4rm-doctor":
                        is_cmd = True
                    elif content.startswith("docker compose"):
                        is_cmd = True
                    elif re.match(r"^(brew|apt|apt-get|docker|docker-compose|grpcurl|make|python3|pip|kubectl|twine|mkdocs|virtualenv|git|go|newgrp|usermod)\s+", content):
                        is_cmd = True
                    elif re.match(r"^python\s+-m\b", content):
                        is_cmd = True

                    if is_cmd:
                        inline_commands.append((path, i + 1, content))

    def report(items: list[Tuple[str, int, str]], title: str) -> None:
        nonlocal rc
        if items:
            print(f"\n[FAIL] {title}: {len(items)} issue(s)")
            for p, ln, snip in items:
                print(f"  - {p}:{ln}: {snip}")
            rc = 1
        else:
            print(f"[OK] {title}")

    report(numbered_bad_style, "Numbered list style '1)' should be '1.'")
    report(missing_blank_before_ordered, "Missing blank line before ordered list")
    report(missing_blank_before_unordered, "Missing blank line before unordered list")
    report(inline_commands, "Inline commands should be in fenced code blocks")

    return rc


if __name__ == "__main__":
    sys.exit(check_docs())
