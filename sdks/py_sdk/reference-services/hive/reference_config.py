#!/usr/bin/env python3
"""Reference service configuration loading and hot-reload helpers."""

from __future__ import annotations

import copy
import json
import logging
import os
import threading
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Mapping, Optional

try:
    import tomllib
except Exception:  # pragma: no cover - fallback for non-3.11 compatibility
    tomllib = None


LOGGER = logging.getLogger(__name__)


_DEFAULT_DB_DIR = str(Path.cwd() / ".reference_services_state")
_DEFAULT_CONFIG_FILE = ""
_DEFAULT_RELOAD_INTERVAL_SECONDS = 2.5
_SUPPORTED_CONFIG_BACKENDS = {"file", "env", "etcd", "consul"}

_DEFAULT_PORTS = {
    "registry": 50052,
    "router": 50051,
    "scheduler": 50053,
}


@dataclass(frozen=True)
class ReferenceServiceConfig:
    """Computed configuration for a reference service."""

    # Shared settings
    config_backend: str
    config_file_path: str
    db_dir: str
    reload_interval_seconds: float

    # Cross-service addresses / ports
    registry_host: str
    registry_port: int
    router_host: str
    router_port: int
    scheduler_host: str
    scheduler_port: int

    # Per-service database paths
    registry_db_path: str
    router_db_path: str
    scheduler_db_path: str

    # Per-service behavior knobs
    registry_heartbeat_timeout_seconds: float
    registry_cleanup_interval_seconds: float
    router_max_queue_size: int

    # Shared shutdown behavior
    shutdown_grace_seconds: float


def _coerce_int(value: Any, default: int, minimum: int = 0) -> int:
    try:
        number = int(value)
    except (TypeError, ValueError):
        return default
    return max(number, minimum)


def _coerce_float(value: Any, default: float, minimum: float = 0.0) -> float:
    try:
        number = float(value)
    except (TypeError, ValueError):
        return default
    return max(number, minimum)


def _coerce_str(value: Any, default: str) -> str:
    if value is None:
        return default
    text = str(value).strip()
    return text if text else default


def _coerce_backend(value: Any) -> str:
    candidate = _coerce_str(value, "file").lower()
    if candidate in _SUPPORTED_CONFIG_BACKENDS:
        return candidate
    if candidate and candidate != "" and candidate != "file":
        LOGGER.warning("Unknown config backend %r; falling back to file backend", candidate)
    return "file"


def _as_mapping(value: Any) -> Mapping[str, Any]:
    if isinstance(value, Mapping):
        return value
    return {}


def _load_config_file(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {}

    try:
        raw = path.read_bytes()
    except OSError:
        return {}

    if path.suffix.lower() == ".toml":
        if tomllib is None:
            LOGGER.warning("Unable to parse TOML config because tomllib is unavailable")
            return {}
        try:
            payload = tomllib.loads(raw.decode("utf-8"))
            if isinstance(payload, Mapping):
                return copy.deepcopy(dict(payload))
            return {}
        except Exception:
            LOGGER.exception("Failed to parse TOML config file %s", path)
            return {}

    try:
        payload = json.loads(raw.decode("utf-8"))
        if isinstance(payload, Mapping):
            return copy.deepcopy(dict(payload))
    except Exception:
        LOGGER.exception("Failed to parse JSON config file %s", path)
    return {}


def _load_reference_payload(config_backend: str, file_path: str) -> dict[str, Any]:
    if not file_path:
        return {}

    if config_backend in {"etcd", "consul"}:
        LOGGER.warning(
            "Backend %s is not yet integrated; using file-backed config if REFERENCE_CONFIG_FILE is present",
            config_backend,
        )

    if config_backend == "env":
        return {}

    return _load_config_file(Path(file_path))


def _service_overrides(file_data: Mapping[str, Any], service_name: str) -> Mapping[str, Any]:
    service_name = service_name.lower()
    merged: dict[str, Any] = {}

    services = _as_mapping(file_data.get("services"))
    merged.update(_as_mapping(services.get(service_name)))

    merged.update(_as_mapping(file_data.get(service_name)))
    return merged


def _shared_overrides(file_data: Mapping[str, Any]) -> Mapping[str, Any]:
    return _as_mapping(file_data.get("global"))


def _resolve_db_dir(service_name: str, file_data: Mapping[str, Any]) -> str:
    shared = _shared_overrides(file_data)
    service = _service_overrides(file_data, service_name)

    db_dir = os.getenv(
        "REFERENCE_SERVICE_DB_DIR",
        _coerce_str(service.get("db_dir"), _coerce_str(shared.get("db_dir"), _DEFAULT_DB_DIR)),
    )
    return str(Path(db_dir))


def _resolve_port(
    service_name: str,
    service_data: Mapping[str, Any],
    shared: Mapping[str, Any],
) -> int:
    env_key = f"{service_name.upper()}_PORT"
    explicit = os.getenv(env_key)
    if explicit is not None:
        return _coerce_int(explicit, _DEFAULT_PORTS.get(service_name, 0), minimum=1)

    value = service_data.get("port", shared.get("port"))
    if isinstance(value, (int, float)):
        return _coerce_int(value, _DEFAULT_PORTS.get(service_name, 0), minimum=1)
    return _DEFAULT_PORTS.get(service_name, 0)


def _resolve_host(service_name: str, service_data: Mapping[str, Any], shared: Mapping[str, Any], fallback: str) -> str:
    env_key = f"{service_name.upper()}_HOST"
    explicit = os.getenv(env_key)
    if explicit is not None:
        return _coerce_str(explicit, fallback)

    value = service_data.get("host", shared.get("host"))
    if isinstance(value, str):
        return value.strip() or fallback
    return fallback


def _resolve_db_path(service_name: str, file_data: Mapping[str, Any]) -> str:
    env_key = f"{service_name.upper()}_DB_PATH"
    db_dir = _resolve_db_dir(service_name, file_data)
    explicit = os.getenv(env_key)
    if explicit is not None:
        return _coerce_str(explicit, "")

    service = _service_overrides(file_data, service_name)
    shared = _shared_overrides(file_data)

    db_path = service.get("db_path", shared.get("db_path"))
    if db_path is not None:
        return _coerce_str(db_path, "")

    return str(Path(db_dir) / f"{service_name}.sqlite3")


def _resolve_reload_interval(file_data: Mapping[str, Any]) -> float:
    shared = _shared_overrides(file_data)
    env_value = os.getenv("REFERENCE_CONFIG_RELOAD_SECONDS")
    if env_value is not None:
        return _coerce_float(env_value, _DEFAULT_RELOAD_INTERVAL_SECONDS, minimum=0.0)

    file_value = shared.get("config_reload_seconds", shared.get("reload_seconds"))
    if file_value is not None:
        return _coerce_float(file_value, _DEFAULT_RELOAD_INTERVAL_SECONDS, minimum=0.0)
    return _DEFAULT_RELOAD_INTERVAL_SECONDS


def load_reference_service_config(service_name: str) -> ReferenceServiceConfig:
    service_name = service_name.lower()
    if service_name not in _DEFAULT_PORTS:
        raise ValueError(f"Unsupported service_name: {service_name}")

    config_backend = _coerce_backend(os.getenv("REFERENCE_CONFIG_BACKEND"))
    file_path = _coerce_str(os.getenv("REFERENCE_CONFIG_FILE"), _DEFAULT_CONFIG_FILE)
    if config_backend in {"env"}:
        file_data: dict[str, Any] = {}
    else:
        file_path = file_path or ""
        file_data = _load_reference_payload(config_backend, file_path)

    shared = _shared_overrides(file_data)
    service = _service_overrides(file_data, service_name)

    registry_host = _resolve_host(
        "registry",
        _service_overrides(file_data, "registry"),
        shared,
        fallback="localhost",
    )
    router_host = _resolve_host(
        "router",
        _service_overrides(file_data, "router"),
        shared,
        fallback="localhost",
    )
    scheduler_host = _resolve_host(
        "scheduler",
        _service_overrides(file_data, "scheduler"),
        shared,
        fallback="localhost",
    )

    reload_seconds = _resolve_reload_interval(file_data)

    return ReferenceServiceConfig(
        config_backend=config_backend,
        config_file_path=file_path,
        db_dir=_resolve_db_dir(service_name, file_data),
        reload_interval_seconds=reload_seconds,
        registry_host=registry_host,
        registry_port=_resolve_port("registry", _service_overrides(file_data, "registry"), shared),
        router_host=router_host,
        router_port=_resolve_port("router", _service_overrides(file_data, "router"), shared),
        scheduler_host=scheduler_host,
        scheduler_port=_resolve_port("scheduler", _service_overrides(file_data, "scheduler"), shared),
        registry_db_path=_resolve_db_path("registry", file_data),
        router_db_path=_resolve_db_path("router", file_data),
        scheduler_db_path=_resolve_db_path("scheduler", file_data),
        registry_heartbeat_timeout_seconds=_coerce_float(
            os.getenv("REFERENCE_REGISTRY_HEARTBEAT_TIMEOUT_SECONDS", service.get("heartbeat_timeout_seconds")),
            _coerce_float(
                shared.get("heartbeat_timeout_seconds"),
                300.0,
                minimum=0.1,
            ),
            minimum=0.1,
        ),
        registry_cleanup_interval_seconds=_coerce_float(
            os.getenv("REFERENCE_REGISTRY_CLEANUP_INTERVAL_SECONDS", service.get("cleanup_interval_seconds")),
            _coerce_float(
                shared.get("cleanup_interval_seconds"),
                60.0,
                minimum=0.1,
            ),
            minimum=0.1,
        ),
        router_max_queue_size=_coerce_int(
            os.getenv("REFERENCE_ROUTER_MAX_QUEUE_SIZE", service.get("max_queue_size")),
            _coerce_int(shared.get("max_queue_size"), 100, minimum=1),
            minimum=1,
        ),
        shutdown_grace_seconds=_coerce_float(
            os.getenv("REFERENCE_SHUTDOWN_GRACE_SECONDS", shared.get("shutdown_grace_seconds")),
            5.0,
            minimum=0.0,
        ),
    )


class ReferenceServiceConfigWatcher:
    """Background refresher for on-disk-backed reference service config."""

    def __init__(
        self,
        service_name: str,
        initial_config: Optional[ReferenceServiceConfig] = None,
    ):
        self.service_name = service_name.lower()
        self._config = initial_config or load_reference_service_config(self.service_name)
        self._lock = threading.Lock()
        self._stop = threading.Event()
        self._thread = threading.Thread(
            target=self._watch_loop,
            daemon=True,
            name=f"reference-config-watcher:{self.service_name}",
        )
        self._last_error_at = 0.0

        if self._config.reload_interval_seconds > 0:
            self._thread.start()

    @property
    def config(self) -> ReferenceServiceConfig:
        with self._lock:
            return self._config

    def close(self) -> None:
        self._stop.set()
        if self._thread.is_alive():
            self._thread.join(timeout=1.0)

    def _reload(self) -> None:
        try:
            latest = load_reference_service_config(self.service_name)
        except Exception:
            LOGGER.exception("Failed to refresh %s reference config", self.service_name)
            self._last_error_at = time.time()
            return

        with self._lock:
            previous = self._config
            if latest != previous:
                self._config = latest
                LOGGER.info("Reference config updated for %s", self.service_name)

    def _watch_loop(self) -> None:
        while not self._stop.wait(self._interval_seconds()):
            if self._stop.is_set():
                return
            self._reload()

    def _interval_seconds(self) -> float:
        with self._lock:
            return max(0.1, self._config.reload_interval_seconds)


def start_reference_service_config_watcher(
    service_name: str,
    initial_config: Optional[ReferenceServiceConfig] = None,
) -> ReferenceServiceConfigWatcher:
    return ReferenceServiceConfigWatcher(
        service_name=service_name,
        initial_config=initial_config,
    )
