#!/usr/bin/env python3

"""Utilities for deterministic graceful shutdown and in-flight tracking."""

import contextlib
import logging
import os
import threading
import time
from typing import Callable, Iterator, Optional


def _resolve_shutdown_grace_period(default_seconds: float = 5.0) -> float:
    """Return configured shutdown grace period in seconds."""
    raw = os.getenv("REFERENCE_SHUTDOWN_GRACE_SECONDS", str(default_seconds))
    try:
        value = float(raw)
    except (TypeError, ValueError):
        return float(default_seconds)
    return max(0.0, value)


class ReferenceServiceShutdownCoordinator:
    """Coordinate graceful shutdown and track in-flight RPCs."""

    def __init__(
        self,
        service_name: str,
        grace_period_seconds: float = 5.0,
        poll_interval_seconds: float = 0.05,
    ):
        self.service_name = service_name
        self.grace_period_seconds = float(grace_period_seconds)
        self._poll_interval_seconds = max(0.05, float(poll_interval_seconds))
        self._is_draining = False
        self._active_requests = 0
        self._method_requests: dict[str, int] = {}
        self._lock = threading.Lock()
        self._drain_cv = threading.Condition(self._lock)

    @property
    def is_draining(self) -> bool:
        return self._is_draining

    @property
    def active_request_count(self) -> int:
        with self._lock:
            return self._active_requests

    def request_shutdown(self) -> None:
        with self._lock:
            if not self._is_draining:
                self._is_draining = True
            self._drain_cv.notify_all()

    @contextlib.contextmanager
    def track_request(self, method: str) -> Iterator[None]:
        with self._drain_cv:
            self._active_requests += 1
            self._method_requests[method] = self._method_requests.get(method, 0) + 1
            self._drain_cv.notify_all()

        try:
            yield
        finally:
            with self._drain_cv:
                self._active_requests = max(0, self._active_requests - 1)
                current = self._method_requests.get(method, 0) - 1
                if current <= 0:
                    self._method_requests.pop(method, None)
                else:
                    self._method_requests[method] = current
                self._drain_cv.notify_all()

    def wait_for_inflight(self, timeout_seconds: Optional[float] = None) -> bool:
        """Wait until all tracked in-flight requests complete.

        Returns True if drained before timeout, False otherwise.
        """
        deadline = None if timeout_seconds is None else (time.monotonic() + timeout_seconds)
        with self._drain_cv:
            while self._active_requests > 0:
                if deadline is None:
                    self._drain_cv.wait(self._poll_interval_seconds)
                    continue

                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    return False
                self._drain_cv.wait(min(self._poll_interval_seconds, remaining))
            return True

    def stop_server(
        self,
        grpc_server,
        *,
        logger: Optional[logging.Logger] = None,
        pre_stop_hook: Optional[Callable[[], None]] = None,
        stop_wait_seconds: Optional[float] = None,
    ) -> None:
        """Begin graceful shutdown and wait for in-flight messages and RPCs."""
        logger = logger or logging.getLogger(f"shutdown.{self.service_name}")
        self.request_shutdown()
        if pre_stop_hook is not None:
            pre_stop_hook()

        timeout_seconds = (
            stop_wait_seconds
            if stop_wait_seconds is not None
            else self.grace_period_seconds
        )
        if timeout_seconds > 0 and not self.wait_for_inflight(timeout_seconds):
            logger.warning(
                "Shutdown wait timed out after %.2fs with %s in-flight request(s) on %s",
                timeout_seconds,
                self.active_request_count,
                self.service_name,
            )

        if grpc_server is None:
            return

        stopper = grpc_server.stop(self.grace_period_seconds)
        stopper.wait(self.grace_period_seconds + 1.0)
