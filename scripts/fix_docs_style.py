#!/usr/bin/env python3
from __future__ import annotations

import os
import re
from typing import List

DOCS_ROOT = "documentation"


def iter_markdown_files(root: str):
    for dirpath, _, filenames in os.walk(root):
        for fn in sorted(filenames):
            if fn.endswith(".md"):
                yield os.path.join(dirpath, fn)


def compute_in_fence_flags(lines: List[str]) -> List[bool]:
    flags = [False] * len(lines)
    in_fence = False
    fence_delim = None
    for i, line in enumerate(lines):
        s = line.strip()
        if s.startswith("```") or s.startswith("~~~"):
            token = s[:3]
            if not in_fence:
                in_fence = True
                fence_delim = token
            elif token == fence_delim:
                in_fence = False
                fence_delim = None
            flags[i] = True
            continue
        if in_fence:
            flags[i] = True
    return flags


ordered_re = re.compile(r"^\s*\d+\.\s")
unordered_re = re.compile(r"^\s*[-*+]\s")


def fix_spacing_before_lists(path: str) -> bool:
    with open(path, "r", encoding="utf-8") as fh:
        lines = fh.read().splitlines()

    flags = compute_in_fence_flags(lines)
    changed = False

    i = 0
    while i < len(lines):
        if flags[i]:
            i += 1
            continue
        line = lines[i]
        if ordered_re.match(line) or unordered_re.match(line):
            # find previous visible, non-fence, non-empty line
            j = i - 1
            while j >= 0 and (flags[j] or lines[j].strip() == "" or lines[j].strip().startswith("```") or lines[j].strip().startswith("~~~")):
                j -= 1
            prev = lines[j] if j >= 0 else ""
            # If previous visible line is not another list item, insert blank line
            if j >= 0 and not (ordered_re.match(prev) or unordered_re.match(prev)):
                # Insert a blank line before this list item
                lines.insert(i, "")
                flags.insert(i, False)
                changed = True
                i += 1  # skip the inserted blank line
        i += 1

    if changed:
        with open(path, "w", encoding="utf-8") as fh:
            fh.write("\n".join(lines) + "\n")
    return changed


def main() -> int:
    changed_any = False
    for path in iter_markdown_files(DOCS_ROOT):
        if fix_spacing_before_lists(path):
            print(f"[fixed] {path}")
            changed_any = True
    print("Done." if changed_any else "No changes needed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
