#!/usr/bin/env python3
from __future__ import annotations

import argparse
import re
from pathlib import Path

try:
    import tomllib
except ModuleNotFoundError:  # pragma: no cover - fallback for Python<3.11
    import tomli as tomllib  # type: ignore


CLOSED_STATUSES = {"done", "complete", "completed", "closed"}
PLAN_OPEN_ITEM_RE = re.compile(r"^\s*-\s+`(?P<key>I\d+)`")
PROMPT_QUEUE_LINE_RE = re.compile(r"^\s*(Active|Current)\s+tranche\s+queue:\s*(?P<body>.+)$", re.IGNORECASE)
TRANCHE_KEY_RE = re.compile(r"\bI\d+\b")


def _extract_markdown_section(text: str, heading: str) -> list[str]:
    lines = text.splitlines()
    start_index = None
    for index, line in enumerate(lines):
        if line.strip() == f"## {heading}":
            start_index = index + 1
            break
    if start_index is None:
        return []

    section_lines: list[str] = []
    for line in lines[start_index:]:
        if line.startswith("## "):
            break
        section_lines.append(line)
    return section_lines


def _load_authority_open_tranches(tranches_path: Path) -> tuple[list[str], list[str]]:
    errors: list[str] = []
    try:
        raw = tomllib.loads(tranches_path.read_text(encoding="utf-8"))
    except Exception as exc:
        return [], [f"{tranches_path}: unable to parse TOML: {exc}"]

    tranches = raw.get("tranches")
    if not isinstance(tranches, list):
        return [], [f"{tranches_path}: expected [[tranches]] list."]

    open_tranches: list[str] = []
    for index, tranche in enumerate(tranches, start=1):
        if not isinstance(tranche, dict):
            errors.append(f"{tranches_path}: tranche #{index} must be a table.")
            continue
        key = tranche.get("key")
        status = tranche.get("status")
        if not isinstance(key, str) or not TRANCHE_KEY_RE.fullmatch(key):
            errors.append(f"{tranches_path}: tranche #{index} has invalid key: {key!r}")
            continue
        if not isinstance(status, str):
            errors.append(f"{tranches_path}: tranche {key} missing string status.")
            continue
        if status.strip().lower() not in CLOSED_STATUSES:
            open_tranches.append(key)

    return open_tranches, errors


def _parse_open_tranches_from_plan(plan_path: Path) -> tuple[list[str], bool, list[str]]:
    errors: list[str] = []
    section_lines = _extract_markdown_section(
        plan_path.read_text(encoding="utf-8"), "Open Work Tranches"
    )
    if not section_lines:
        return [], False, [f"{plan_path}: missing `## Open Work Tranches` section."]

    open_tranches: list[str] = []
    explicit_none = False
    saw_bullet = False

    for line in section_lines:
        stripped = line.strip()
        if not stripped.startswith("-"):
            continue
        saw_bullet = True
        if re.search(r"\bnone\b", stripped, flags=re.IGNORECASE):
            explicit_none = True
        match = PLAN_OPEN_ITEM_RE.match(line)
        if match:
            open_tranches.append(match.group("key"))

    if not saw_bullet:
        errors.append(f"{plan_path}: `## Open Work Tranches` must include bullet entries.")
    if not open_tranches and not explicit_none:
        errors.append(
            f"{plan_path}: `## Open Work Tranches` must explicitly declare open tranche bullets or a `None` bullet."
        )

    return open_tranches, explicit_none, errors


def _parse_prompt_objective_state(prompt_path: Path) -> tuple[list[str], bool, list[str]]:
    errors: list[str] = []
    section_lines = _extract_markdown_section(
        prompt_path.read_text(encoding="utf-8"), "Objective"
    )
    if not section_lines:
        return [], False, [f"{prompt_path}: missing `## Objective` section."]

    queue_ids: list[str] = []
    explicit_no_open = False

    for line in section_lines:
        stripped = line.strip()
        if not stripped:
            continue
        if "no open tranche" in stripped.lower():
            explicit_no_open = True
        queue_line_match = PROMPT_QUEUE_LINE_RE.match(stripped)
        if queue_line_match:
            queue_ids.extend(TRANCHE_KEY_RE.findall(queue_line_match.group("body")))

    if not queue_ids and not explicit_no_open:
        errors.append(
            f"{prompt_path}: `## Objective` must explicitly declare `Active tranche queue: ...` or `No open tranche ...`."
        )

    deduped_queue_ids = list(dict.fromkeys(queue_ids))
    return deduped_queue_ids, explicit_no_open, errors


def reconcile_dispatch_authority(
    tranches_path: Path, plan_path: Path, prompt_path: Path
) -> list[str]:
    errors: list[str] = []
    authority_open, authority_errors = _load_authority_open_tranches(tranches_path)
    errors.extend(authority_errors)

    if not plan_path.exists():
        errors.append(f"{plan_path}: file not found")
        return errors
    if not prompt_path.exists():
        errors.append(f"{prompt_path}: file not found")
        return errors

    plan_open, plan_none, plan_errors = _parse_open_tranches_from_plan(plan_path)
    errors.extend(plan_errors)

    prompt_queue, prompt_none, prompt_errors = _parse_prompt_objective_state(prompt_path)
    errors.extend(prompt_errors)

    if authority_open != plan_open:
        errors.append(
            "Open tranche mismatch between dispatch authority and IMPLEMENTATION_PLAN.md: "
            f"authority={authority_open or ['none']} vs plan={plan_open or ['none']}"
        )
    if authority_open and plan_none:
        errors.append(
            "Phantom-open condition: IMPLEMENTATION_PLAN.md declares `None` while dispatch authority has open tranches."
        )
    if not authority_open and not plan_none and plan_open:
        errors.append(
            "IMPLEMENTATION_PLAN.md declares open tranches while dispatch authority is empty."
        )

    if authority_open and prompt_none:
        errors.append(
            "Phantom-open condition: PROMPT.md objective declares no open tranche while dispatch authority has open tranches."
        )
    if not authority_open and prompt_queue:
        errors.append(
            "PROMPT.md objective declares active tranches while dispatch authority has no open tranches."
        )
    if prompt_queue and prompt_queue != authority_open:
        errors.append(
            "Active tranche queue mismatch between PROMPT.md and dispatch authority: "
            f"prompt={prompt_queue} vs authority={authority_open}"
        )

    return errors


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Reconcile dispatch authority and prevent phantom-open tranches across "
            ".yarli/tranches.toml, IMPLEMENTATION_PLAN.md, and PROMPT.md."
        )
    )
    parser.add_argument(
        "--tranches",
        default=".yarli/tranches.toml",
        help="Path to dispatch authority tranche metadata (default: .yarli/tranches.toml)",
    )
    parser.add_argument(
        "--plan",
        default="IMPLEMENTATION_PLAN.md",
        help="Path to implementation plan markdown (default: IMPLEMENTATION_PLAN.md)",
    )
    parser.add_argument(
        "--prompt",
        default="PROMPT.md",
        help="Path to prompt markdown (default: PROMPT.md)",
    )
    args = parser.parse_args()

    tranches_path = Path(args.tranches)
    plan_path = Path(args.plan)
    prompt_path = Path(args.prompt)

    if not tranches_path.exists():
        print(f"[FAIL] {tranches_path}: file not found")
        return 1

    errors = reconcile_dispatch_authority(tranches_path, plan_path, prompt_path)
    if errors:
        for error in errors:
            print(f"[FAIL] {error}")
        return 1

    authority_open, _ = _load_authority_open_tranches(tranches_path)
    queue_repr = "none" if not authority_open else ", ".join(authority_open)
    print(
        "[OK] dispatch authority reconciled and no phantom-open conditions detected "
        f"(open queue: {queue_repr})"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
