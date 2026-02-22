#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path
from typing import Any

try:
    import tomllib
except ModuleNotFoundError:  # pragma: no cover - fallback for Python<3.11
    import tomli as tomllib  # type: ignore


def _as_positive_int(value: Any, field_name: str, errors: list[str]) -> int | None:
    if not isinstance(value, int):
        errors.append(f"{field_name} must be an integer (got {type(value).__name__}).")
        return None
    if value <= 0:
        errors.append(f"{field_name} must be > 0 (got {value}).")
        return None
    return value


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Check long-loop reliability invariants in yarli.toml."
    )
    parser.add_argument(
        "--config",
        default="yarli.toml",
        help="Path to YARLI config (default: yarli.toml)",
    )
    args = parser.parse_args()

    config_path = Path(args.config)
    if not config_path.exists():
        print(f"[FAIL] {config_path}: file not found")
        return 1

    try:
        config = tomllib.loads(config_path.read_text(encoding="utf-8"))
    except Exception as exc:
        print(f"[FAIL] {config_path}: unable to parse TOML: {exc}")
        return 1

    errors: list[str] = []

    queue = config.get("queue") or {}
    execution = config.get("execution") or {}
    budgets = config.get("budgets") or {}

    lease_ttl = _as_positive_int(
        queue.get("lease_ttl_seconds"), "queue.lease_ttl_seconds", errors
    )
    command_timeout = _as_positive_int(
        execution.get("command_timeout_seconds"),
        "execution.command_timeout_seconds",
        errors,
    )

    if lease_ttl is not None and command_timeout is not None:
        if lease_ttl < command_timeout:
            errors.append(
                "queue.lease_ttl_seconds must be >= execution.command_timeout_seconds "
                f"(got {lease_ttl} < {command_timeout})."
            )
        else:
            print(
                "[OK] lease/timeout invariant: "
                f"queue.lease_ttl_seconds={lease_ttl} >= execution.command_timeout_seconds={command_timeout}"
            )

    task_tokens_raw = budgets.get("max_task_total_tokens")
    run_tokens_raw = budgets.get("max_run_total_tokens")

    if task_tokens_raw is None and run_tokens_raw is None:
        print(
            "[WARN] token-budget invariant skipped: "
            "budgets.max_task_total_tokens and budgets.max_run_total_tokens are both unset "
            "(no token-budget guardrails will be enforced)."
        )
    elif task_tokens_raw is None or run_tokens_raw is None:
        errors.append(
            "budgets.max_task_total_tokens and budgets.max_run_total_tokens must both be set when either is configured."
        )
    else:
        task_tokens = _as_positive_int(
            task_tokens_raw, "budgets.max_task_total_tokens", errors
        )
        run_tokens = _as_positive_int(
            run_tokens_raw, "budgets.max_run_total_tokens", errors
        )
        if task_tokens is not None and run_tokens is not None:
            if run_tokens < task_tokens:
                errors.append(
                    "budgets.max_run_total_tokens must be >= budgets.max_task_total_tokens "
                    f"(got {run_tokens} < {task_tokens})."
                )
            else:
                print(
                    "[OK] token-budget invariant: "
                    f"budgets.max_run_total_tokens={run_tokens} >= budgets.max_task_total_tokens={task_tokens}"
                )

    if errors:
        for error in errors:
            print(f"[FAIL] {error}")
        return 1

    print("[OK] yarli.toml long-loop invariants passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
