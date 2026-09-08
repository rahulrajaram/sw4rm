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

"""Fast regression tests for crash-conformance evidence integrity."""

from __future__ import annotations

from contextlib import contextmanager
import json
import subprocess
import sys
import textwrap
import time
from pathlib import Path

import pytest

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from conformance_contract import (  # noqa: E402
    REQUIRED_SCENARIOS,
    SCHEMA_VERSION,
    inventory_errors,
    scorecard_errors,
    summarize,
)
from harness import CrashHarness, read_child_line  # noqa: E402
from test_crash_scenarios import _assert_recorded  # noqa: E402


def _completed(name: str, returncode: int, *markers: str) -> subprocess.CompletedProcess:
    return subprocess.CompletedProcess(
        [sys.executable, "run_one.py", name],
        returncode,
        "\n".join(markers) + ("\n" if markers else ""),
        "",
    )


@contextmanager
def _binary_child(source: str):
    """Run a tiny pipe-writing child with bounded, scoped cleanup."""
    child = subprocess.Popen(
        [sys.executable, "-u", "-c", source],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=False,
        bufsize=0,
    )
    try:
        yield child
    finally:
        if child.poll() is None:
            child.kill()
        child.wait(timeout=5)
        if child.stdout is not None:
            child.stdout.close()
        if child.stderr is not None:
            child.stderr.close()


def test_read_child_line_preserves_events_from_one_os_write() -> None:
    source = "import os, time; os.write(1, b'FIRST\\nSECOND\\n'); time.sleep(5)"
    with _binary_child(source) as child:
        assert read_child_line(child, timeout=1) == "FIRST"
        assert read_child_line(child, timeout=1) == "SECOND"


def test_read_child_line_partial_event_obeys_deadline() -> None:
    source = "import os, time; os.write(1, b'PARTIAL'); time.sleep(5)"
    started = time.monotonic()
    with _binary_child(source) as child:
        with pytest.raises(RuntimeError, match="deadline"):
            read_child_line(child, timeout=0.1)
    assert time.monotonic() - started < 1.0


@pytest.mark.parametrize(
    ("source", "message"),
    [
        ("import os; os.write(1, b'EOF')", "exited before completing"),
        ("import os, time; os.write(1, b'x' * 8193); time.sleep(5)", "exceeds 8192"),
    ],
)
def test_read_child_line_rejects_eof_and_oversized_events(
    source: str, message: str
) -> None:
    with _binary_child(source) as child:
        with pytest.raises(RuntimeError, match=message):
            read_child_line(child, timeout=1)


def test_run_one_exception_has_no_accepted_verdict_and_still_cleans_up() -> None:
    """A raised scenario is a harness error, even if cleanup runs."""
    code = textwrap.dedent(
        f"""
        import sys
        sys.path.insert(0, {str(HERE)!r})
        import run_one

        class FakeHarness:
            def stop_all(self):
                print("CLEANUP", flush=True)

        def exploding_scenario(_harness):
            raise RuntimeError("injected scenario failure")

        run_one.CrashHarness = FakeHarness
        run_one.SCENARIOS = [("SX", "synthetic invariant", exploding_scenario)]
        sys.argv = ["run_one.py", "SX"]
        run_one.main()
        """
    )
    completed = subprocess.run(
        [sys.executable, "-c", code],
        cwd=str(HERE.parent.parent),
        capture_output=True,
        text=True,
        timeout=10,
        check=False,
    )

    assert completed.returncode != 0
    assert "CLEANUP" in completed.stdout
    assert "RESULT:SX:" not in completed.stdout


def test_harness_cleans_up_only_its_automatic_workdir() -> None:
    harness = CrashHarness()
    workdir = harness.workdir
    try:
        assert workdir.is_dir()
    finally:
        harness.stop_all()
    assert not workdir.exists()


def test_harness_preserves_caller_supplied_workdir(tmp_path: Path) -> None:
    workdir = tmp_path / "caller-workdir"
    harness = CrashHarness(workdir=workdir)
    marker = workdir / "retain.txt"
    marker.write_text("caller-owned")
    harness.stop_all()

    assert workdir.is_dir()
    assert marker.read_text() == "caller-owned"


def test_unexpected_scenario_exception_is_error_row_and_main_fails(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    import run_scenarios

    def exploding_scenario(_harness: CrashHarness) -> tuple[str, str]:
        raise RuntimeError("injected scenario failure")

    monkeypatch.setattr(
        run_scenarios,
        "SCENARIOS",
        tuple((name, f"invariant for {name}", exploding_scenario) for name in REQUIRED_SCENARIOS),
    )
    scorecard = tmp_path / "scorecard.json"
    monkeypatch.setattr(
        sys,
        "argv",
        ["run_scenarios.py", "--scorecard", str(scorecard)],
    )

    assert run_scenarios.main() == 1
    payload = json.loads(scorecard.read_text())
    assert payload["summary"] == {"pass": 0, "fail": 0, "error": 6}
    assert {row["status"] for row in payload["results"]} == {"error"}


def test_nonzero_child_with_forged_fail_marker_is_rejected() -> None:
    with pytest.raises(AssertionError, match="harness exited 1"):
        _assert_recorded("S1", _completed("S1", 1, "RESULT:S1:fail"))


@pytest.mark.parametrize("status", ["pass", "fail"])
def test_zero_exit_recorded_outcomes_are_accepted(status: str) -> None:
    _assert_recorded("S1", _completed("S1", 0, f"RESULT:S1:{status}"))


@pytest.mark.parametrize(
    ("name", "markers"),
    [
        ("S1", ("RESULT:S1:pass", "RESULT:S1:fail")),
        ("S1", ("RESULT:S1:fail", "RESULT:S1:fail")),
        ("S1", ("RESULT:S2a:pass",)),
        ("S1", ("RESULT:S1:skip",)),
    ],
)
def test_contradictory_duplicate_or_wrong_markers_are_rejected(
    name: str, markers: tuple[str, ...]
) -> None:
    with pytest.raises(AssertionError):
        _assert_recorded(name, _completed(name, 0, *markers))


def _result(name: str, status: str = "pass") -> dict[str, object]:
    return {
        "scenario": name,
        "invariant": f"invariant for {name}",
        "status": status,
        "detail": f"measured {status} for {name}",
        "duration_s": 0.01,
    }


def _scorecard(statuses: dict[str, str] | None = None) -> dict[str, object]:
    results = [_result(name, (statuses or {}).get(name, "pass")) for name in REQUIRED_SCENARIOS]
    return {
        "schema_version": SCHEMA_VERSION,
        "results": results,
        "summary": summarize(results),
    }


def test_old_four_green_scorecard_is_incomplete() -> None:
    old_results = [_result(name) for name in ("S1", "S2a", "S2b", "S4")]
    payload = {
        "schema_version": 1,
        "results": old_results,
        "summary": {"pass": 4, "fail": 0},
    }
    errors = scorecard_errors(payload)
    assert "unsupported scorecard schema" in errors
    assert "missing scenario: S3" in errors
    assert "missing scenario: S5" in errors


def test_duplicate_scorecard_scenario_is_rejected() -> None:
    payload = _scorecard()
    payload["results"] = list(payload["results"]) + [_result("S1")]
    payload["summary"] = summarize(payload["results"])

    assert "duplicate scenario: S1" in scorecard_errors(payload)


def test_forged_scorecard_summary_is_rejected() -> None:
    payload = _scorecard()
    payload["summary"] = {"pass": 5, "fail": 1, "error": 0}

    assert "summary does not match results" in scorecard_errors(payload)


def test_measured_failure_is_valid_but_harness_error_is_rejected() -> None:
    measured_failure = _scorecard({"S3": "fail"})
    assert scorecard_errors(measured_failure) == ()

    harness_error = _scorecard({"S3": "error"})
    errors = scorecard_errors(harness_error)
    assert "S3: harness error" in errors


def test_registered_scenario_inventory_matches_acceptance_contract() -> None:
    from run_scenarios import SCENARIOS

    names = tuple(name for name, _invariant, _scenario in SCENARIOS)
    assert inventory_errors(names) == ()
