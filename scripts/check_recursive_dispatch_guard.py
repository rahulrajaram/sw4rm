#!/usr/bin/env python3
from __future__ import annotations

import argparse
import re
from pathlib import Path

TASK_LINE_RE = re.compile(r"^\s*-\s+\*\*(Build|Test|Verify A|Verify B)\*\*:\s*(?P<body>.+)$")
FORBIDDEN_COMMAND = "yarli run"

PROMPT_REQUIREMENTS = [
    "Do not run `yarli run` from inside tranche commands",
    "Only the operator shell may invoke `yarli run`",
]


def _scan_plan(plan_path: Path) -> list[str]:
    errors: list[str] = []
    lines = plan_path.read_text(encoding="utf-8").splitlines()
    for line_no, line in enumerate(lines, 1):
        match = TASK_LINE_RE.match(line)
        if match is None:
            continue
        task_body = match.group("body").lower()
        if FORBIDDEN_COMMAND in task_body:
            errors.append(
                f"{plan_path}:{line_no}: tranche task line contains forbidden recursive dispatch: {line.strip()}"
            )
    return errors


def _scan_prompt(prompt_path: Path) -> list[str]:
    errors: list[str] = []
    text = prompt_path.read_text(encoding="utf-8")
    for requirement in PROMPT_REQUIREMENTS:
        if requirement not in text:
            errors.append(
                f"{prompt_path}: missing required recursive-dispatch guard text: {requirement}"
            )
    return errors


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Validate anti-recursive-dispatch guardrails in prompt/plan files."
    )
    parser.add_argument(
        "--prompt",
        default="PROMPT.md",
        help="Path to PROMPT.md (default: PROMPT.md)",
    )
    parser.add_argument(
        "--plan",
        default="IMPLEMENTATION_PLAN.md",
        help="Path to IMPLEMENTATION_PLAN.md (default: IMPLEMENTATION_PLAN.md)",
    )
    args = parser.parse_args()

    prompt_path = Path(args.prompt)
    plan_path = Path(args.plan)

    errors: list[str] = []
    if not prompt_path.exists():
        errors.append(f"{prompt_path}: file not found")
    if not plan_path.exists():
        errors.append(f"{plan_path}: file not found")
    if errors:
        for error in errors:
            print(f"[FAIL] {error}")
        return 1

    errors.extend(_scan_prompt(prompt_path))
    errors.extend(_scan_plan(plan_path))

    if errors:
        for error in errors:
            print(f"[FAIL] {error}")
        return 1

    print(
        "[OK] anti-recursive-dispatch guardrails: prompt constraints present and no tranche Build/Test/Verify step calls `yarli run`."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
