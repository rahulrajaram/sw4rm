import importlib.util
import json
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
MODULE_PATH = REPO_ROOT / "tests" / "inter_swarm_testbed" / "smoke_workflow.py"
MANIFEST_PATH = REPO_ROOT / "tests" / "inter_swarm_testbed" / "bootstrap_manifest.json"
COMPOSE_PATH = REPO_ROOT / "tests" / "inter_swarm_testbed" / "docker-compose.multi-swarm.yml"


def _load_module():
    spec = importlib.util.spec_from_file_location("inter_swarm_smoke_workflow", MODULE_PATH)
    assert spec is not None
    assert spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def test_manifest_exposes_canonical_smoke_workflow_commands() -> None:
    manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    commands = manifest["bootstrap_commands"]
    assert (
        commands["smoke_workflow_bounded"]
        == "python tests/inter_swarm_testbed/smoke_workflow.py --mode bounded"
    )
    assert (
        commands["smoke_workflow_compose"]
        == "python tests/inter_swarm_testbed/smoke_workflow.py --mode compose --require-docker"
    )
    assert (
        commands["ci_smoke_target"]
        == "python tests/inter_swarm_testbed/ci_smoke_target.py --summary-json artifacts/verification/i55-ci-smoke-summary.json --log-file artifacts/verification/i55-ci-smoke-workflow.log"
    )


def test_smoke_workflow_step_plan_is_repeatable() -> None:
    workflow = _load_module()
    bounded_steps = workflow.build_steps("bounded", COMPOSE_PATH)
    compose_steps = workflow.build_steps("compose", COMPOSE_PATH)

    assert [step.name for step in bounded_steps] == [
        "bootstrap-layout-validation",
        "compose-config-validation",
    ]
    assert [step.name for step in compose_steps] == [
        "bootstrap-layout-validation",
        "compose-config-validation",
        "compose-up",
        "compose-ps",
        "compose-down",
    ]


def test_smoke_workflow_cli_defaults_to_bounded_mode() -> None:
    workflow = _load_module()
    parser = workflow.build_parser()
    args = parser.parse_args([])
    assert args.mode == "bounded"
