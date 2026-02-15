import importlib.util
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
MODULE_PATH = REPO_ROOT / "tests" / "inter_swarm_testbed" / "ci_smoke_target.py"


def _load_module():
    spec = importlib.util.spec_from_file_location("inter_swarm_ci_smoke_target", MODULE_PATH)
    assert spec is not None
    assert spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def test_validate_summary_accepts_expected_bounded_outcomes() -> None:
    ci_target = _load_module()
    errors = ci_target.validate_summary(
        [
            {"name": "bootstrap-layout-validation", "status": "ok"},
            {"name": "compose-config-validation", "status": "skipped"},
        ]
    )
    assert errors == []


def test_validate_summary_rejects_missing_required_step() -> None:
    ci_target = _load_module()
    errors = ci_target.validate_summary(
        [
            {"name": "bootstrap-layout-validation", "status": "ok"},
        ]
    )
    assert errors == ["missing required step 'compose-config-validation'"]


def test_validate_summary_rejects_invalid_bootstrap_status() -> None:
    ci_target = _load_module()
    errors = ci_target.validate_summary(
        [
            {"name": "bootstrap-layout-validation", "status": "skipped"},
            {"name": "compose-config-validation", "status": "ok"},
        ]
    )
    assert errors == [
        "step 'bootstrap-layout-validation' has invalid status 'skipped' (allowed: ['ok'])"
    ]
