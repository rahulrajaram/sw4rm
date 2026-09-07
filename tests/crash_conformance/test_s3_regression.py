"""Prove the real S3 experiment detects loss of atomic snapshot writes."""

from __future__ import annotations

import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from harness import CrashHarness  # noqa: E402
import scenario_s3  # noqa: E402


def test_s3_detects_overwriting_the_confirmed_snapshot(monkeypatch) -> None:
    source_builder = scenario_s3._writer_script

    def source_with_live_file_write(path: Path) -> str:
        source = source_builder(path)
        # Only the generated child changes. Its first write confirms a valid
        # baseline; its second write truncates the live snapshot before SIGKILL.
        needle = "builtins.open = synchronized_open\n"
        override = (
            "def overwrite_live_file(records, order):\n"
            "    with open(path, 'w') as stream:\n"
            "        stream.write('non-atomic replacement')\n"
            "persistence.save_records = overwrite_live_file\n"
            + needle
        )
        assert needle in source
        return source.replace(needle, override, 1)

    monkeypatch.setattr(scenario_s3, "_writer_script", source_with_live_file_write)
    harness = CrashHarness()
    try:
        status, detail = scenario_s3.scenario_s3_buffer_write_survives_kill(harness)
    finally:
        harness.stop_all()
    assert status == "fail"
    assert "confirmed persistence bytes changed" in detail
