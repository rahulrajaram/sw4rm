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

"""Run one crash scenario by ID: python3 run_one.py S2b

Prints RESULT:<scenario>:<pass|fail> after successful cleanup so the
pytest wrapper can distinguish a recorded FAIL row (a scorecard entry —
allowed) from a hung or crashed scenario (a test failure).
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "sdks" / "py_sdk"))

from harness import CrashHarness  # noqa: E402
from run_scenarios import SCENARIOS  # noqa: E402


def main() -> int:
    name = sys.argv[1]
    scenario = dict((s[0], s[2]) for s in SCENARIOS)[name]
    harness = CrashHarness()
    try:
        status, detail = scenario(harness)
        if status not in ("pass", "fail") or not isinstance(detail, str) or not detail:
            raise ValueError(f"invalid scenario result: {status!r}, {detail!r}")
    finally:
        harness.stop_all()
    print(f"[{status.upper():4}] {name}: {detail}")
    print(f"RESULT:{name}:{status}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
