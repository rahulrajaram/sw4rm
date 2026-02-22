from __future__ import annotations

import sys
from concurrent import futures
from pathlib import Path

import grpc
import pytest

HIVE_DIR = Path(__file__).resolve().parents[1] / "reference-services" / "hive"
if str(HIVE_DIR) not in sys.path:
    sys.path.insert(0, str(HIVE_DIR))

from health_service import (  # noqa: E402
    SERVICE_UNKNOWN,
    SERVING,
    add_reference_health_service,
    HealthCheckRequest,
    HealthCheckResponse,
)  # type: ignore # noqa: F401,E402


def _start_health_server(service_name: str) -> tuple[grpc.Server, int]:
    server = grpc.server(futures.ThreadPoolExecutor(max_workers=4))
    add_reference_health_service(server, service_names=(service_name,))
    port = server.add_insecure_port("127.0.0.1:0")
    server.start()
    return server, port


def _health_check(status_service_name: str, port: int) -> int:
    request = HealthCheckRequest(service=status_service_name)
    channel = grpc.insecure_channel(f"127.0.0.1:{port}")
    try:
        call = channel.unary_unary(
            "/grpc.health.v1.Health/Check",
            request_serializer=request.SerializeToString,
            response_deserializer=HealthCheckResponse.FromString,
        )
        return call(request, timeout=2.0).status
    finally:
        channel.close()


def _stop_server(server: grpc.Server) -> None:
    server.stop(0.1).wait(timeout=1.0)


@pytest.mark.parametrize(
    "service_name",
    (
        "sw4rm.registry.RegistryService",
        "sw4rm.router.RouterService",
        "sw4rm.scheduler.SchedulerService",
    ),
)
def test_reference_health_check_reports_serving(service_name: str) -> None:
    server, port = _start_health_server(service_name)
    try:
        assert _health_check("", port) == SERVING
        assert _health_check(service_name, port) == SERVING
        assert _health_check("sw4rm.unknown.Service", port) == SERVICE_UNKNOWN
    finally:
        _stop_server(server)


def test_reference_health_watch_yields_initial_status() -> None:
    service_name = "sw4rm.router.RouterService"
    server, port = _start_health_server(service_name)
    try:
        channel = grpc.insecure_channel(f"127.0.0.1:{port}")
        try:
            watch_call = channel.unary_stream(
                "/grpc.health.v1.Health/Watch",
                request_serializer=lambda request: request.SerializeToString(),
                response_deserializer=HealthCheckResponse.FromString,
            )
            updates = watch_call(HealthCheckRequest(service=service_name), timeout=2.0)
            first = next(iter(updates))
            assert first.status == SERVING
        finally:
            channel.close()
    finally:
        _stop_server(server)
