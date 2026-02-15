from __future__ import annotations

from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
from check_dispatch_authority import reconcile_dispatch_authority


def _write(path: Path, content: str) -> None:
    path.write_text(content, encoding="utf-8")


def test_reconcile_dispatch_authority_success(tmp_path: Path) -> None:
    tranches_path = tmp_path / "tranches.toml"
    plan_path = tmp_path / "IMPLEMENTATION_PLAN.md"
    prompt_path = tmp_path / "PROMPT.md"

    _write(
        tranches_path,
        """
version = 1

[[tranches]]
key = "I53"
status = "complete"

[[tranches]]
key = "I54"
status = "incomplete"

[[tranches]]
key = "I55"
status = "incomplete"
""",
    )
    _write(
        plan_path,
        """
# Plan

## Open Work Tranches

- `I54` Promote workflow.
- `I55` Integrate evidence.

## Other
""",
    )
    _write(
        prompt_path,
        """
# Prompt

## Objective

Active tranche queue: `I54` -> `I55`.

## Other
""",
    )

    assert reconcile_dispatch_authority(tranches_path, plan_path, prompt_path) == []


def test_reconcile_detects_plan_phantom_none(tmp_path: Path) -> None:
    tranches_path = tmp_path / "tranches.toml"
    plan_path = tmp_path / "IMPLEMENTATION_PLAN.md"
    prompt_path = tmp_path / "PROMPT.md"

    _write(
        tranches_path,
        """
version = 1

[[tranches]]
key = "I53"
status = "incomplete"
""",
    )
    _write(
        plan_path,
        """
# Plan

## Open Work Tranches

- None. No open tranches.

## Other
""",
    )
    _write(
        prompt_path,
        """
# Prompt

## Objective

Active tranche queue: `I53`.

## Other
""",
    )

    errors = reconcile_dispatch_authority(tranches_path, plan_path, prompt_path)
    assert any("Phantom-open condition: IMPLEMENTATION_PLAN.md" in error for error in errors)


def test_reconcile_detects_prompt_phantom_none(tmp_path: Path) -> None:
    tranches_path = tmp_path / "tranches.toml"
    plan_path = tmp_path / "IMPLEMENTATION_PLAN.md"
    prompt_path = tmp_path / "PROMPT.md"

    _write(
        tranches_path,
        """
version = 1

[[tranches]]
key = "I53"
status = "incomplete"
""",
    )
    _write(
        plan_path,
        """
# Plan

## Open Work Tranches

- `I53` Dispatch control.

## Other
""",
    )
    _write(
        prompt_path,
        """
# Prompt

## Objective

No open tranche is currently queued.

## Other
""",
    )

    errors = reconcile_dispatch_authority(tranches_path, plan_path, prompt_path)
    assert any("Phantom-open condition: PROMPT.md" in error for error in errors)
