# Copyright 2025 Rahul Rajaram
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0

"""Dependency-free structural checks for the optional Temporal example."""

import ast
from pathlib import Path


EXAMPLE = (
    Path(__file__).resolve().parents[1]
    / "examples"
    / "temporal"
    / "approval_workflow.py"
)


def _tree() -> ast.Module:
    source = EXAMPLE.read_text(encoding="utf-8")
    compile(source, str(EXAMPLE), "exec")
    return ast.parse(source, filename=str(EXAMPLE))


def _decorator_names(tree: ast.Module) -> list[str]:
    names: list[str] = []
    for node in ast.walk(tree):
        if isinstance(node, (ast.ClassDef, ast.FunctionDef, ast.AsyncFunctionDef)):
            for decorator in node.decorator_list:
                if isinstance(decorator, ast.Attribute) and isinstance(
                    decorator.value, ast.Name
                ):
                    names.append(f"{decorator.value.id}.{decorator.attr}")
    return names


def test_temporal_contract_is_present_without_importing_temporalio() -> None:
    tree = _tree()
    source = EXAMPLE.read_text(encoding="utf-8")
    decorators = _decorator_names(tree)
    assert decorators.count("workflow.defn") == 1
    assert decorators.count("workflow.run") == 1
    assert decorators.count("workflow.signal") == 1

    calls = {
        node.func.attr
        for node in ast.walk(tree)
        if isinstance(node, ast.Call)
        and isinstance(node.func, ast.Attribute)
        and isinstance(node.func.value, ast.Name)
        and node.func.value.id == "workflow"
    }
    assert {"wait_condition"}.issubset(calls)
    assert "all_handlers_finished" in ast.unparse(tree)
    assert "TimeoutError" in ast.unparse(tree)
    assert "from sw4rm_policies.quorum import" in source
    rendered = ast.unparse(tree)
    assert "evaluate(" in rendered
    assert "aggregate_votes(" in rendered
    assert "should_escalate(" in rendered
    assert "apply_policy(" in rendered
    assert "PolicyDecision" in rendered
    assert 'status = "approved"' not in rendered


def test_temporal_isolated_from_policy_package() -> None:
    policy_root = Path(__file__).resolve().parents[1] / "sw4rm_policies"
    if policy_root.exists():
        assert not any(
            "temporalio" in path.read_text(encoding="utf-8")
            for path in policy_root.rglob("*.py")
        )
