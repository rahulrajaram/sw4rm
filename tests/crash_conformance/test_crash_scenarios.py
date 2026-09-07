# Copyright 2025 Rahul Rajaram
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""Pytest wrapper for the crash-injection conformance scenarios.

Runs each scenario as a subprocess so a hung or crashed scenario cannot
take down the suite (per the campaign's finite-breaker discipline: each
scenario gets a hard timeout and its failure is recorded, not masked).
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

import pytest

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from conformance_contract import REQUIRED_SCENARIOS  # noqa: E402


def _run_scenario(name: str) -> subprocess.CompletedProcess:
    script = HERE / "run_one.py"
    return subprocess.run(
        [sys.executable, str(script), name],
        capture_output=True,
        text=True,
        timeout=240,
        check=False,
    )


def _assert_recorded(name: str, completed: subprocess.CompletedProcess) -> None:
    out = completed.stdout + completed.stderr
    markers = tuple(line for line in completed.stdout.splitlines() if line.startswith("RESULT:"))
    assert completed.returncode == 0, f"{name}: harness exited {completed.returncode}\n{out[-4000:]}"
    assert markers in ((f"RESULT:{name}:pass",), (f"RESULT:{name}:fail",)), (
        f"{name}: scenario produced no verdict (hung or crashed).\n"
        f"stdout:\n{completed.stdout[-2000:]}\nstderr:\n{completed.stderr[-2000:]}"
    )
    # A FAIL verdict is allowed (it is a scorecard row); a missing verdict
    # or an unexpected crash is a test failure.


@pytest.mark.parametrize("name", REQUIRED_SCENARIOS)
def test_scenario_records_measured_outcome(name: str) -> None:
    _assert_recorded(name, _run_scenario(name))
