#!/usr/bin/env python3
"""Repeatable smoke workflow runner for the inter-swarm testbed."""

from __future__ import annotations

import argparse
import json
import shlex
import shutil
import subprocess
import sys
import time
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Sequence


REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_MANIFEST = REPO_ROOT / "tests" / "inter_swarm_testbed" / "bootstrap_manifest.json"
DEFAULT_COMPOSE = REPO_ROOT / "tests" / "inter_swarm_testbed" / "docker-compose.multi-swarm.yml"


@dataclass(frozen=True)
class Step:
    name: str
    command: list[str]


@dataclass
class StepResult:
    name: str
    command: str
    status: str
    returncode: int | None
    duration_seconds: float
    stdout: str
    stderr: str


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Run bounded or compose-mode smoke checks for inter-swarm testbed."
    )
    parser.add_argument(
        "--mode",
        choices=("bounded", "compose"),
        default="bounded",
        help="bounded = no container bring-up, compose = full compose up/ps/down cycle.",
    )
    parser.add_argument(
        "--manifest",
        type=Path,
        default=DEFAULT_MANIFEST,
        help="Path to bootstrap manifest json.",
    )
    parser.add_argument(
        "--compose-file",
        type=Path,
        default=DEFAULT_COMPOSE,
        help="Path to docker compose file.",
    )
    parser.add_argument(
        "--timeout-seconds",
        type=int,
        default=180,
        help="Per-command timeout for bounded execution.",
    )
    parser.add_argument(
        "--require-docker",
        action="store_true",
        help="Fail instead of skipping docker compose checks when docker is unavailable.",
    )
    parser.add_argument(
        "--summary-json",
        type=Path,
        default=None,
        help="Optional path to write structured run summary.",
    )
    return parser


def build_steps(mode: str, compose_file: Path) -> list[Step]:
    steps = [
        Step(
            name="bootstrap-layout-validation",
            command=[
                sys.executable,
                "-m",
                "pytest",
                "sdks/py_sdk/tests/test_inter_swarm_testbed_bootstrap.py",
                "-q",
            ],
        ),
        Step(
            name="compose-config-validation",
            command=["docker", "compose", "-f", str(compose_file), "config", "--quiet"],
        ),
    ]
    if mode == "compose":
        steps.extend(
            [
                Step(
                    name="compose-up",
                    command=[
                        "docker",
                        "compose",
                        "-f",
                        str(compose_file),
                        "up",
                        "--build",
                        "-d",
                    ],
                ),
                Step(
                    name="compose-ps",
                    command=["docker", "compose", "-f", str(compose_file), "ps"],
                ),
                Step(
                    name="compose-down",
                    command=["docker", "compose", "-f", str(compose_file), "down", "-v"],
                ),
            ]
        )
    return steps


def load_manifest(manifest_path: Path) -> dict:
    return json.loads(manifest_path.read_text(encoding="utf-8"))


def docker_compose_available() -> bool:
    if shutil.which("docker") is None:
        return False
    probe = subprocess.run(
        ["docker", "compose", "version"],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
        check=False,
    )
    return probe.returncode == 0


def run_step(step: Step, timeout_seconds: int) -> StepResult:
    start = time.monotonic()
    completed = subprocess.run(
        step.command,
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
        check=False,
        timeout=timeout_seconds,
    )
    duration = time.monotonic() - start
    return StepResult(
        name=step.name,
        command=" ".join(shlex.quote(token) for token in step.command),
        status="ok" if completed.returncode == 0 else "failed",
        returncode=completed.returncode,
        duration_seconds=round(duration, 3),
        stdout=completed.stdout,
        stderr=completed.stderr,
    )


def print_step_result(result: StepResult) -> None:
    print(f"[{result.status.upper()}] {result.name} ({result.duration_seconds:.3f}s)")
    print(f"  cmd: {result.command}")
    if result.stdout.strip():
        print(result.stdout.rstrip())
    if result.stderr.strip():
        print(result.stderr.rstrip(), file=sys.stderr)


def main(argv: Sequence[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    manifest_path = args.manifest.resolve()
    compose_file = args.compose_file.resolve()

    for required_path in (manifest_path, compose_file):
        if not required_path.exists():
            print(f"[ERROR] Required file missing: {required_path}", file=sys.stderr)
            return 2

    load_manifest(manifest_path)
    results: list[StepResult] = []
    skip_docker_checks = not docker_compose_available()
    if skip_docker_checks and (args.require_docker or args.mode == "compose"):
        print(
            "[ERROR] docker compose is unavailable but this run requires docker.",
            file=sys.stderr,
        )
        return 3

    for step in build_steps(args.mode, compose_file):
        if step.name.startswith("compose-") and skip_docker_checks:
            skipped = StepResult(
                name=step.name,
                command=" ".join(shlex.quote(token) for token in step.command),
                status="skipped",
                returncode=None,
                duration_seconds=0.0,
                stdout="docker compose unavailable; step skipped in bounded mode.",
                stderr="",
            )
            print_step_result(skipped)
            results.append(skipped)
            continue

        try:
            result = run_step(step, timeout_seconds=args.timeout_seconds)
        except subprocess.TimeoutExpired:
            timed_out = StepResult(
                name=step.name,
                command=" ".join(shlex.quote(token) for token in step.command),
                status="failed",
                returncode=None,
                duration_seconds=float(args.timeout_seconds),
                stdout="",
                stderr=f"timed out after {args.timeout_seconds}s",
            )
            print_step_result(timed_out)
            results.append(timed_out)
            if args.summary_json:
                args.summary_json.write_text(
                    json.dumps([asdict(item) for item in results], indent=2) + "\n",
                    encoding="utf-8",
                )
            return 1

        print_step_result(result)
        results.append(result)
        if result.status == "failed":
            if args.summary_json:
                args.summary_json.write_text(
                    json.dumps([asdict(item) for item in results], indent=2) + "\n",
                    encoding="utf-8",
                )
            return 1

    if args.summary_json:
        args.summary_json.write_text(
            json.dumps([asdict(item) for item in results], indent=2) + "\n",
            encoding="utf-8",
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
