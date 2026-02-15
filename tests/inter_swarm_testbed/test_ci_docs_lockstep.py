import json
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
MANIFEST_PATH = REPO_ROOT / "tests" / "inter_swarm_testbed" / "bootstrap_manifest.json"
RUNBOOK_PATH = REPO_ROOT / "documentation" / "production" / "inter-swarm-transport-testbed.md"
WORKFLOW_PATH = REPO_ROOT / ".github" / "workflows" / "ci-inter-swarm-smoke-evidence.yml"
CI_COMMAND = (
    "python tests/inter_swarm_testbed/ci_smoke_target.py --summary-json "
    "artifacts/verification/i55-ci-smoke-summary.json --log-file "
    "artifacts/verification/i55-ci-smoke-workflow.log"
)


def test_manifest_ci_smoke_target_matches_runbook_command() -> None:
    manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    assert manifest["bootstrap_commands"]["ci_smoke_target"] == CI_COMMAND

    runbook = RUNBOOK_PATH.read_text(encoding="utf-8")
    assert CI_COMMAND in runbook


def test_workflow_runs_ci_target_and_docs_checks() -> None:
    workflow = WORKFLOW_PATH.read_text(encoding="utf-8")
    assert "python tests/inter_swarm_testbed/ci_smoke_target.py" in workflow
    assert "python scripts/check_docs_style.py" in workflow
    assert "python -m mkdocs build" in workflow
    assert "actions/upload-artifact@v4" in workflow
