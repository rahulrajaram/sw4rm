from __future__ import annotations

import subprocess
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT_PATH = REPO_ROOT / "sdks" / "cl_sdk" / "test" / "reference_grpc_integration.py"


def test_cl_reference_grpc_integration_script_exits_zero() -> None:
    completed = subprocess.run(
        [sys.executable, str(SCRIPT_PATH), "--timeout-seconds", "40"],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
        check=False,
        timeout=90,
    )
    assert completed.returncode == 0, (
        "Integration script failed.\n"
        f"stdout:\n{completed.stdout}\n"
        f"stderr:\n{completed.stderr}"
    )
