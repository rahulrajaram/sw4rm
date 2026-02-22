#!/usr/bin/env python3
"""gRPC health check service registration for reference services."""

from __future__ import annotations

from typing import Iterable, Optional, Sequence

import grpc
from google.protobuf import descriptor_pb2, descriptor_pool, message_factory


_HEALTH_SERVICE_NAME = "grpc.health.v1.Health"
_HEALTH_FILE_NAME = "grpc_health.proto"


def _health_file_descriptor() -> descriptor_pb2.FileDescriptorProto:
    file_proto = descriptor_pb2.FileDescriptorProto()
    file_proto.name = _HEALTH_FILE_NAME
    file_proto.package = "grpc.health.v1"
    file_proto.syntax = "proto3"

    request = file_proto.message_type.add()
    request.name = "HealthCheckRequest"
    request_service_field = request.field.add()
    request_service_field.name = "service"
    request_service_field.number = 1
    request_service_field.label = descriptor_pb2.FieldDescriptorProto.LABEL_OPTIONAL
    request_service_field.type = descriptor_pb2.FieldDescriptorProto.TYPE_STRING

    response = file_proto.message_type.add()
    response.name = "HealthCheckResponse"
    status_enum = response.enum_type.add()
    status_enum.name = "ServingStatus"
    for name, number in (
        ("UNKNOWN", 0),
        ("SERVING", 1),
        ("NOT_SERVING", 2),
        ("SERVICE_UNKNOWN", 3),
    ):
        value = status_enum.value.add()
        value.name = name
        value.number = number
    response_status_field = response.field.add()
    response_status_field.name = "status"
    response_status_field.number = 1
    response_status_field.label = descriptor_pb2.FieldDescriptorProto.LABEL_OPTIONAL
    response_status_field.type = descriptor_pb2.FieldDescriptorProto.TYPE_ENUM
    response_status_field.type_name = ".grpc.health.v1.HealthCheckResponse.ServingStatus"

    service = file_proto.service.add()
    service.name = "Health"
    check = service.method.add()
    check.name = "Check"
    check.input_type = ".grpc.health.v1.HealthCheckRequest"
    check.output_type = ".grpc.health.v1.HealthCheckResponse"
    watch = service.method.add()
    watch.name = "Watch"
    watch.input_type = ".grpc.health.v1.HealthCheckRequest"
    watch.output_type = ".grpc.health.v1.HealthCheckResponse"
    watch.server_streaming = True

    return file_proto


_POOL = descriptor_pool.Default()

try:
    _POOL.FindFileByName(_HEALTH_FILE_NAME)
except Exception:
    _POOL.Add(_health_file_descriptor())

_FACTORY = message_factory.MessageFactory(_POOL)
HealthCheckRequest = _FACTORY.GetPrototype(
    _POOL.FindMessageTypeByName("grpc.health.v1.HealthCheckRequest")
)
HealthCheckResponse = _FACTORY.GetPrototype(
    _POOL.FindMessageTypeByName("grpc.health.v1.HealthCheckResponse")
)

_SERVING_STATUS = _POOL.FindEnumTypeByName(
    "grpc.health.v1.HealthCheckResponse.ServingStatus"
)
UNKNOWN = _SERVING_STATUS.values_by_name["UNKNOWN"].number
SERVING = _SERVING_STATUS.values_by_name["SERVING"].number
NOT_SERVING = _SERVING_STATUS.values_by_name["NOT_SERVING"].number
SERVICE_UNKNOWN = _SERVING_STATUS.values_by_name["SERVICE_UNKNOWN"].number


class ReferenceHealthService:
    """Simple gRPC health check servicer implementation."""

    def __init__(self, serving_service_names: Optional[Sequence[str]] = None):
        self.serving_service_names = {
            str(service_name) for service_name in (serving_service_names or ())
        }

    def Check(self, request, context):  # noqa: N802  # gRPC method style
        status = self._status_for_service(request.service)
        return HealthCheckResponse(status=status)

    def Watch(self, request, context):  # noqa: N802  # gRPC method style
        yield HealthCheckResponse(status=self._status_for_service(request.service))

    def _status_for_service(self, service_name: str) -> int:
        if not service_name:
            return SERVING
        if service_name in self.serving_service_names:
            return SERVING
        return SERVICE_UNKNOWN


def add_reference_health_service(
    server: grpc.Server,
    service_names: Optional[Iterable[str]] = None,
) -> ReferenceHealthService:
    """Register `grpc.health.v1.Health` with the provided service names as healthy."""
    servicer = ReferenceHealthService(list(service_names) if service_names else None)

    check_handler = grpc.unary_unary_rpc_method_handler(
        servicer.Check,
        request_deserializer=HealthCheckRequest.FromString,
        response_serializer=lambda response: response.SerializeToString(),
    )
    watch_handler = grpc.unary_stream_rpc_method_handler(
        servicer.Watch,
        request_deserializer=HealthCheckRequest.FromString,
        response_serializer=lambda response: response.SerializeToString(),
    )
    rpc_handlers = {"Check": check_handler, "Watch": watch_handler}
    generic_handler = grpc.method_handlers_generic_handler(
        _HEALTH_SERVICE_NAME,
        rpc_handlers,
    )
    server.add_generic_rpc_handlers((generic_handler,))
    return servicer
