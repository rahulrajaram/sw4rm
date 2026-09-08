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

"""Regression coverage for honest S5 failure classification."""

from __future__ import annotations

import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from harness import CrashHarness  # noqa: E402
import scenario_s5  # noqa: E402


def test_s5_records_sdk_dedup_failure_as_repeated_side_effect(monkeypatch) -> None:
    """A broken SDK lookup must produce a measured red S5 row, not a timeout."""
    source_builder = scenario_s5._child_source

    def source_with_disabled_sdk_lookup() -> str:
        source = source_builder()
        needle = "from sw4rm.activity_buffer import PersistentActivityBuffer, is_terminal_state\n"
        override = (
            needle
            + "# Test-only fault injection: disable the real SDK dedup lookup.\n"
            + "PersistentActivityBuffer.get_by_idempotency_token = lambda self, token: None\n"
        )
        assert needle in source
        return source.replace(needle, override, 1)

    monkeypatch.setattr(scenario_s5, "_child_source", source_with_disabled_sdk_lookup)
    harness = CrashHarness()
    try:
        status, detail = scenario_s5.scenario_s5_idempotent_redelivery(harness)
    finally:
        harness.stop_all()

    assert status == "fail"
    assert "repeated the side effect" in detail
