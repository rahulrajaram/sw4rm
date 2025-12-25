from __future__ import annotations

from typing import Any


class ConnectorClient:
    """Client for interacting with the ConnectorService.

    The ConnectorService manages tool providers and their capabilities.
    """

    def __init__(self, channel: Any) -> None:
        """Initialize the ConnectorClient.

        Args:
            channel: gRPC channel to use for communication
        """
        self._channel = channel
        try:
            from sw4rm.protos import connector_pb2, connector_pb2_grpc  # type: ignore
            self._pb2 = connector_pb2
            self._stub = connector_pb2_grpc.ConnectorServiceStub(channel)
        except Exception:
            self._pb2 = None
            self._stub = None

    def register_provider(
        self,
        provider_id: str,
        tools: list[dict[str, Any]]
    ) -> Any:
        """Register a tool provider with its available tools.

        Args:
            provider_id: Unique identifier for the provider
            tools: List of tool descriptors, each containing:
                - tool_name (str): Name of the tool
                - input_schema (str): JSON Schema or URL for input
                - output_schema (str): JSON Schema or URL for output
                - idempotent (bool): Whether the tool is idempotent
                - needs_worktree (bool): Whether the tool needs a worktree
                - default_timeout_s (int): Default timeout in seconds
                - max_concurrency (int): Maximum concurrent executions
                - side_effects (str): Side effects like "filesystem", "network"

        Returns:
            ProviderRegisterResponse with ok (bool) and reason (str) fields

        Raises:
            RuntimeError: If protobuf stubs are not generated
        """
        if not self._stub:
            raise RuntimeError("Protobuf stubs not generated. Run `make protos`.")

        tool_descriptors = [
            self._pb2.ToolDescriptor(**tool) for tool in tools
        ]
        req = self._pb2.ProviderRegisterRequest(
            provider_id=provider_id,
            tools=tool_descriptors
        )
        return self._stub.RegisterProvider(req)

    def describe_tools(self, provider_id: str) -> Any:
        """Describe the tools available from a specific provider.

        Args:
            provider_id: Unique identifier for the provider

        Returns:
            DescribeToolsResponse with a list of ToolDescriptor objects

        Raises:
            RuntimeError: If protobuf stubs are not generated
        """
        if not self._stub:
            raise RuntimeError("Protobuf stubs not generated. Run `make protos`.")
        req = self._pb2.DescribeToolsRequest(provider_id=provider_id)
        return self._stub.DescribeTools(req)

