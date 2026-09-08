"""Pure acceptance checks for the campaign's six required crash scenarios.

A measured failure is valid evidence. An absent scenario, malformed result,
or harness error is not a completed conformance run.
"""

from __future__ import annotations

import math
from collections.abc import Mapping, Sequence
from typing import Any

REQUIRED_SCENARIOS = ("S1", "S2a", "S2b", "S3", "S4", "S5")
RESULT_STATUSES = ("pass", "fail", "error")
SCHEMA_VERSION = 2


def inventory_errors(names: Sequence[str]) -> tuple[str, ...]:
    expected = frozenset(REQUIRED_SCENARIOS)
    actual = frozenset(names)
    return (
        tuple(f"missing scenario: {name}" for name in REQUIRED_SCENARIOS if name not in actual)
        + tuple(f"unexpected scenario: {name}" for name in sorted(actual - expected))
        + tuple(f"duplicate scenario: {name}" for name in sorted(actual) if names.count(name) > 1)
    )


def result_errors(result: Mapping[str, Any]) -> tuple[str, ...]:
    name = result.get("scenario")
    duration = result.get("duration_s")
    rules = (
        (isinstance(name, str) and name in REQUIRED_SCENARIOS, "unknown scenario"),
        (result.get("status") in RESULT_STATUSES, "invalid status"),
        (isinstance(result.get("invariant"), str) and bool(result.get("invariant")), "missing invariant"),
        (isinstance(result.get("detail"), str) and bool(result.get("detail")), "missing detail"),
        (type(duration) in (int, float) and math.isfinite(duration) and duration >= 0, "invalid duration"),
    )
    return tuple(f"{name}: {message}" for valid, message in rules if not valid)


def summarize(results: Sequence[Mapping[str, Any]]) -> dict[str, int]:
    return {status: sum(result.get("status") == status for result in results) for status in RESULT_STATUSES}


def scorecard_errors(payload: Mapping[str, Any]) -> tuple[str, ...]:
    results = payload.get("results")
    if not isinstance(results, list) or any(not isinstance(row, dict) for row in results):
        return ("results must be an array of objects",)
    names = tuple(row.get("scenario") for row in results)
    inventory = inventory_errors(names) if all(isinstance(name, str) for name in names) else ("scenario IDs must be strings",)
    return (
        (() if payload.get("schema_version") == SCHEMA_VERSION else ("unsupported scorecard schema",))
        + inventory
        + tuple(error for row in results for error in result_errors(row))
        + (() if payload.get("summary") == summarize(results) else ("summary does not match results",))
        + tuple(f"{row.get('scenario')}: harness error" for row in results if row.get("status") == "error")
    )
