#!/usr/bin/env python3
"""CI smoke target wrapper for inter-swarm testbed evidence collection."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path
from typing import Any


REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_SUMMARY_PATH = REPO_ROOT / "artifacts" / "verification" / "i55-ci-smoke-summary.json"
DEFAULT_LOG_PATH = REPO_ROOT / "artifacts" / "verification" / "i55-ci-smoke-workflow.log"
REQUIRED_STATUS = {
    "bootstrap-layout-validation": {"ok"},
    "compose-config-validation": {"ok", "skipped"},
}


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Run CI-equivalent inter-swarm bounded smoke with evidence checks."
    )
    parser.add_argument(
        "--summary-json",
        type=Path,
        default=DEFAULT_SUMMARY_PATH,
        help="Path where the smoke workflow JSON summary is written.",
    )
    parser.add_argument(
        "--log-file",
        type=Path,
        default=DEFAULT_LOG_PATH,
        help="Path where smoke workflow stdout/stderr transcript is written.",
    )
    parser.add_argument(
        "--timeout-seconds",
        type=int,
        default=180,
        help="Per-command timeout passed to the smoke workflow.",
    )
    return parser


def validate_summary(summary_data: list[dict[str, Any]]) -> list[str]:
    errors: list[str] = []
    by_name = {entry.get("name"): entry for entry in summary_data}
    for step_name, allowed in REQUIRED_STATUS.items():
        step_entry = by_name.get(step_name)
        if step_entry is None:
            errors.append(f"missing required step '{step_name}'")
            continue
        observed = str(step_entry.get("status", ""))
        if observed not in allowed:
            errors.append(
                f"step '{step_name}' has invalid status '{observed}' (allowed: {sorted(allowed)})"
            )
    return errors


def main() -> int:
    args = build_parser().parse_args()
    summary_path = args.summary_json.resolve()
    log_path = args.log_file.resolve()
    summary_path.parent.mkdir(parents=True, exist_ok=True)
    log_path.parent.mkdir(parents=True, exist_ok=True)

    command = [
        sys.executable,
        "tests/inter_swarm_testbed/smoke_workflow.py",
        "--mode",
        "bounded",
        "--timeout-seconds",
        str(args.timeout_seconds),
        "--summary-json",
        str(summary_path),
    ]
    completed = subprocess.run(
        command,
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
        check=False,
    )

    transcript = ""
    if completed.stdout:
        transcript += completed.stdout
    if completed.stderr:
        transcript += completed.stderr
    log_path.write_text(transcript, encoding="utf-8")

    if completed.stdout:
        print(completed.stdout, end="")
    if completed.stderr:
        print(completed.stderr, end="", file=sys.stderr)

    if completed.returncode != 0:
        print(
            f"[ERROR] smoke workflow exited with status {completed.returncode}",
            file=sys.stderr,
        )
        return completed.returncode

    summary_data = json.loads(summary_path.read_text(encoding="utf-8"))
    errors = validate_summary(summary_data)
    if errors:
        for error in errors:
            print(f"[ERROR] {error}", file=sys.stderr)
        return 4

    print(f"[OK] CI smoke target passed. Summary: {summary_path}")
    print(f"[OK] CI smoke transcript captured at: {log_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
