from __future__ import annotations

import json
import sys
import time
from pathlib import Path

HIVE_DIR = Path(__file__).resolve().parents[1] / "reference-services" / "hive"
if str(HIVE_DIR) not in sys.path:
    sys.path.insert(0, str(HIVE_DIR))

from reference_config import (
    ReferenceServiceConfig,
    load_reference_service_config,
    start_reference_service_config_watcher,
)


def _write_config(path: Path, payload: dict) -> None:
    path.write_text(json.dumps(payload), encoding="utf-8")


def _wait_for_reload(predicate, timeout_seconds: float = 2.5) -> bool:
    deadline = time.time() + timeout_seconds
    while time.time() < deadline:
        if predicate():
            return True
        time.sleep(0.05)
    return False


def test_load_reference_service_config_reads_environment_overrides(monkeypatch, tmp_path: Path) -> None:
    db_dir = tmp_path / "runtime"
    monkeypatch.setenv("REFERENCE_SERVICE_DB_DIR", str(db_dir))
    monkeypatch.setenv("REGISTRY_PORT", "53052")
    monkeypatch.setenv("ROUTER_PORT", "53051")
    monkeypatch.setenv("SCHEDULER_PORT", "53053")
    monkeypatch.setenv("REFERENCE_REGISTRY_HEARTBEAT_TIMEOUT_SECONDS", "15")
    monkeypatch.setenv("REFERENCE_REGISTRY_CLEANUP_INTERVAL_SECONDS", "90")
    monkeypatch.setenv("REFERENCE_ROUTER_MAX_QUEUE_SIZE", "256")
    monkeypatch.setenv("REFERENCE_SHUTDOWN_GRACE_SECONDS", "11")

    config = load_reference_service_config("registry")

    assert config.registry_port == 53052
    assert config.router_port == 53051
    assert config.scheduler_port == 53053
    assert config.db_dir == str(db_dir)
    assert config.registry_db_path == str(db_dir / "registry.sqlite3")
    assert config.router_db_path == str(db_dir / "router.sqlite3")
    assert config.scheduler_db_path == str(db_dir / "scheduler.sqlite3")
    assert config.registry_heartbeat_timeout_seconds == 15.0
    assert config.registry_cleanup_interval_seconds == 90.0
    assert config.router_max_queue_size == 256
    assert config.shutdown_grace_seconds == 11.0


def test_load_reference_service_config_from_file(monkeypatch, tmp_path: Path) -> None:
    config_path = tmp_path / "reference-services.json"
    _write_config(
        config_path,
        {
            "global": {
                "host": "global.example",
                "port": 54000,
                "db_dir": str(tmp_path / "from_file"),
                "heartbeat_timeout_seconds": 20,
                "cleanup_interval_seconds": 40,
                "max_queue_size": 128,
                "shutdown_grace_seconds": 7,
                "db_path": str(tmp_path / "shared.sqlite3"),
            },
            "services": {
                "registry": {
                    "host": "registry.example",
                    "port": 54010,
                    "heartbeat_timeout_seconds": 11,
                    "cleanup_interval_seconds": 22,
                    "db_path": str(tmp_path / "registry.sqlite3"),
                },
                "router": {
                    "host": "router.example",
                    "port": 54020,
                },
                "scheduler": {
                    "host": "scheduler.example",
                    "port": 54030,
                },
            },
            "router": {
                "port": 54021,
            },
        },
    )

    monkeypatch.setenv("REFERENCE_CONFIG_BACKEND", "file")
    monkeypatch.setenv("REFERENCE_CONFIG_FILE", str(config_path))
    monkeypatch.setenv("REFERENCE_CONFIG_RELOAD_SECONDS", "0.2")

    config = load_reference_service_config("registry")

    assert config.router_host == "router.example"
    assert config.router_port == 54021
    assert config.registry_host == "registry.example"
    assert config.registry_db_path == str(tmp_path / "registry.sqlite3")
    assert config.router_db_path == str(tmp_path / "shared.sqlite3")
    assert config.router_max_queue_size == 128
    assert config.registry_heartbeat_timeout_seconds == 11.0
    assert config.registry_cleanup_interval_seconds == 22.0
    assert config.shutdown_grace_seconds == 7.0
    assert config.reload_interval_seconds == 0.2


def test_reference_service_config_watcher_refreshes_file_changes(monkeypatch, tmp_path: Path) -> None:
    config_path = tmp_path / "dynamic-config.json"
    _write_config(
        config_path,
        {
            "global": {
                "heartbeat_timeout_seconds": 12,
                "config_reload_seconds": 0.1,
                "db_path": str(tmp_path / "one.sqlite3"),
            }
        },
    )

    monkeypatch.setenv("REFERENCE_CONFIG_BACKEND", "file")
    monkeypatch.setenv("REFERENCE_CONFIG_FILE", str(config_path))

    initial = load_reference_service_config("registry")
    watcher = start_reference_service_config_watcher("registry", initial_config=initial)
    try:
        assert initial.config_backend == "file"
        assert initial.registry_heartbeat_timeout_seconds == 12.0

        _write_config(
            config_path,
            {
                "global": {
                    "heartbeat_timeout_seconds": 24,
                    "config_reload_seconds": 0.1,
                }
            },
        )

        assert _wait_for_reload(
            lambda: watcher.config.registry_heartbeat_timeout_seconds == 24.0,
            timeout_seconds=2.5,
        )

        config: ReferenceServiceConfig = watcher.config
        assert config.reload_interval_seconds >= 0.1
        assert config.registry_heartbeat_timeout_seconds == 24.0
    finally:
        watcher.close()
