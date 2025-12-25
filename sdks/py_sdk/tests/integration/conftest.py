"""Pytest fixtures and configuration for integration tests.

This module provides shared fixtures for integration testing:
- Mock gRPC server setup
- Client fixtures for SchedulerClient, WorktreeClient, ToolClient, etc.
- Skip markers for when real server is not available
- Test environment configuration
"""
import os
import pytest
from unittest.mock import MagicMock, Mock, patch
from typing import Any, Iterator


# Environment-based skip markers
def pytest_configure(config):
    """Register custom markers."""
    config.addinivalue_line(
        "markers", "requires_server: mark test as requiring a real gRPC server"
    )
    config.addinivalue_line(
        "markers", "requires_protos: mark test as requiring generated protobuf stubs"
    )


def should_skip_server_tests() -> bool:
    """Check if tests requiring a real server should be skipped."""
    return os.getenv("SW4RM_INTEGRATION_SERVER", "").lower() != "true"


def should_skip_proto_tests() -> bool:
    """Check if protobuf stubs are available."""
    try:
        from sw4rm.protos import scheduler_pb2, scheduler_pb2_grpc
        return False
    except ImportError:
        return True


# Skip markers
skip_without_server = pytest.mark.skipif(
    should_skip_server_tests(),
    reason="Real gRPC server not available. Set SW4RM_INTEGRATION_SERVER=true to enable."
)

skip_without_protos = pytest.mark.skipif(
    should_skip_proto_tests(),
    reason="Protobuf stubs not generated. Run 'make protos' to enable."
)


# Mock gRPC Channel Fixtures
@pytest.fixture
def mock_grpc_channel() -> MagicMock:
    """Create a mock gRPC channel for testing.

    Returns:
        MagicMock configured as a gRPC channel
    """
    channel = MagicMock()
    channel.close = MagicMock()
    return channel


@pytest.fixture
def mock_scheduler_stub() -> MagicMock:
    """Create a mock SchedulerService stub.

    Returns:
        MagicMock configured with all SchedulerService methods
    """
    stub = MagicMock()

    # Configure default responses
    submit_response = MagicMock()
    submit_response.acknowledged = True
    stub.SubmitTask.return_value = submit_response

    preempt_response = MagicMock()
    preempt_response.acknowledged = True
    stub.RequestPreemption.return_value = preempt_response

    shutdown_response = MagicMock()
    shutdown_response.acknowledged = True
    stub.ShutdownAgent.return_value = shutdown_response

    poll_response = MagicMock()
    poll_response.entries = []
    stub.PollActivityBuffer.return_value = poll_response

    purge_response = MagicMock()
    purge_response.purged_count = 0
    stub.PurgeActivity.return_value = purge_response

    return stub


@pytest.fixture
def mock_worktree_stub() -> MagicMock:
    """Create a mock WorktreeService stub.

    Returns:
        MagicMock configured with all WorktreeService methods
    """
    stub = MagicMock()

    # Configure default responses
    bind_response = MagicMock()
    bind_response.acknowledged = True
    stub.Bind.return_value = bind_response

    unbind_response = MagicMock()
    unbind_response.acknowledged = True
    stub.Unbind.return_value = unbind_response

    status_response = MagicMock()
    status_response.worktree_id = "worktree-1"
    status_response.repo_id = "repo-1"
    status_response.bound = True
    stub.Status.return_value = status_response

    switch_response = MagicMock()
    switch_response.acknowledged = True
    stub.RequestSwitch.return_value = switch_response

    approve_response = MagicMock()
    approve_response.acknowledged = True
    stub.ApproveSwitch.return_value = approve_response

    reject_response = MagicMock()
    reject_response.acknowledged = True
    stub.RejectSwitch.return_value = reject_response

    return stub


@pytest.fixture
def mock_tool_stub() -> MagicMock:
    """Create a mock ToolService stub.

    Returns:
        MagicMock configured with all ToolService methods
    """
    stub = MagicMock()

    # Configure default responses
    call_response = MagicMock()
    call_response.result = b'{"status": "success"}'
    call_response.content_type = "application/json"
    stub.Call.return_value = call_response

    # For streaming calls
    stream_responses = [
        MagicMock(chunk=b'{"partial": 1}'),
        MagicMock(chunk=b'{"partial": 2}'),
    ]
    stub.CallStream.return_value = iter(stream_responses)

    cancel_response = MagicMock()
    cancel_response.acknowledged = True
    stub.Cancel.return_value = cancel_response

    return stub


@pytest.fixture
def mock_negotiation_stub() -> MagicMock:
    """Create a mock NegotiationService stub.

    Returns:
        MagicMock configured with all NegotiationService methods
    """
    stub = MagicMock()

    # Configure default responses
    open_response = MagicMock()
    open_response.acknowledged = True
    stub.Open.return_value = open_response

    propose_response = MagicMock()
    propose_response.acknowledged = True
    stub.Propose.return_value = propose_response

    counter_response = MagicMock()
    counter_response.acknowledged = True
    stub.Counter.return_value = counter_response

    evaluate_response = MagicMock()
    evaluate_response.acknowledged = True
    stub.Evaluate.return_value = evaluate_response

    decide_response = MagicMock()
    decide_response.acknowledged = True
    stub.Decide.return_value = decide_response

    abort_response = MagicMock()
    abort_response.acknowledged = True
    stub.Abort.return_value = abort_response

    return stub


@pytest.fixture
def mock_activity_stub() -> MagicMock:
    """Create a mock ActivityService stub.

    Returns:
        MagicMock configured with all ActivityService methods
    """
    stub = MagicMock()

    # Configure default responses
    append_response = MagicMock()
    append_response.acknowledged = True
    stub.AppendArtifact.return_value = append_response

    list_response = MagicMock()
    list_response.artifacts = []
    stub.ListArtifacts.return_value = list_response

    return stub


# Client Fixtures
@pytest.fixture
def scheduler_client(mock_grpc_channel, mock_scheduler_stub) -> Any:
    """Create a SchedulerClient with mock stub.

    Args:
        mock_grpc_channel: Mock gRPC channel
        mock_scheduler_stub: Mock scheduler stub

    Returns:
        SchedulerClient configured with mocks
    """
    from sw4rm.clients.scheduler import SchedulerClient
    client = SchedulerClient(mock_grpc_channel)
    client._stub = mock_scheduler_stub

    # Mock the protobuf module
    mock_pb2 = MagicMock()
    mock_pb2.SubmitTaskRequest = lambda **kwargs: MagicMock(**kwargs)
    mock_pb2.PreemptRequest = lambda **kwargs: MagicMock(**kwargs)
    mock_pb2.ShutdownAgentRequest = lambda **kwargs: MagicMock(**kwargs)
    mock_pb2.PollActivityBufferRequest = lambda **kwargs: MagicMock(**kwargs)
    mock_pb2.PurgeActivityRequest = lambda **kwargs: MagicMock(**kwargs)
    client._pb2 = mock_pb2

    return client


@pytest.fixture
def worktree_client(mock_grpc_channel, mock_worktree_stub) -> Any:
    """Create a WorktreeClient with mock stub.

    Args:
        mock_grpc_channel: Mock gRPC channel
        mock_worktree_stub: Mock worktree stub

    Returns:
        WorktreeClient configured with mocks
    """
    from sw4rm.clients.worktree import WorktreeClient
    client = WorktreeClient(mock_grpc_channel)
    client._stub = mock_worktree_stub

    # Mock the protobuf module
    mock_pb2 = MagicMock()
    mock_pb2.BindRequest = lambda **kwargs: MagicMock(**kwargs)
    mock_pb2.UnbindRequest = lambda **kwargs: MagicMock(**kwargs)
    mock_pb2.StatusRequest = lambda **kwargs: MagicMock(**kwargs)
    mock_pb2.SwitchRequest = lambda **kwargs: MagicMock(**kwargs)
    mock_pb2.SwitchApprove = lambda **kwargs: MagicMock(**kwargs)
    mock_pb2.SwitchReject = lambda **kwargs: MagicMock(**kwargs)
    client._pb2 = mock_pb2

    return client


@pytest.fixture
def tool_client(mock_grpc_channel, mock_tool_stub) -> Any:
    """Create a ToolClient with mock stub.

    Args:
        mock_grpc_channel: Mock gRPC channel
        mock_tool_stub: Mock tool stub

    Returns:
        ToolClient configured with mocks
    """
    from sw4rm.clients.tool import ToolClient
    client = ToolClient(mock_grpc_channel)
    client._stub = mock_tool_stub

    # Mock the protobuf module
    mock_pb2 = MagicMock()
    mock_pb2.ToolCall = lambda **kwargs: MagicMock(**kwargs)
    client._pb2 = mock_pb2

    return client


@pytest.fixture
def negotiation_client(mock_grpc_channel, mock_negotiation_stub) -> Any:
    """Create a NegotiationClient with mock stub.

    Args:
        mock_grpc_channel: Mock gRPC channel
        mock_negotiation_stub: Mock negotiation stub

    Returns:
        NegotiationClient configured with mocks
    """
    from sw4rm.clients.negotiation import NegotiationClient
    client = NegotiationClient(mock_grpc_channel)
    client._stub = mock_negotiation_stub

    # Mock the protobuf module
    mock_pb2 = MagicMock()
    mock_pb2.NegotiationOpen = lambda **kwargs: MagicMock(**kwargs)
    mock_pb2.Proposal = lambda **kwargs: MagicMock(**kwargs)
    mock_pb2.CounterProposal = lambda **kwargs: MagicMock(**kwargs)
    mock_pb2.Evaluation = lambda **kwargs: MagicMock(**kwargs)
    mock_pb2.Decision = lambda **kwargs: MagicMock(**kwargs)
    mock_pb2.AbortRequest = lambda **kwargs: MagicMock(**kwargs)

    # Mock duration - needs to accept keyword arguments
    mock_duration_module = MagicMock()
    mock_duration_module.Duration = lambda **kwargs: MagicMock(**kwargs)
    mock_pb2.google_dot_protobuf_dot_duration__pb2 = mock_duration_module
    client._pb2 = mock_pb2

    return client


@pytest.fixture
def activity_client(mock_grpc_channel, mock_activity_stub) -> Any:
    """Create an ActivityClient with mock stub.

    Args:
        mock_grpc_channel: Mock gRPC channel
        mock_activity_stub: Mock activity stub

    Returns:
        ActivityClient configured with mocks
    """
    from sw4rm.clients.activity import ActivityClient
    client = ActivityClient(mock_grpc_channel)
    client._stub = mock_activity_stub

    # Mock the protobuf module
    mock_pb2 = MagicMock()
    mock_pb2.Artifact = lambda **kwargs: MagicMock(**kwargs)
    mock_pb2.AppendArtifactRequest = lambda **kwargs: MagicMock(**kwargs)
    mock_pb2.ListArtifactsRequest = lambda **kwargs: MagicMock(**kwargs)
    client._pb2 = mock_pb2

    return client


# Mock Server Setup Helpers
@pytest.fixture
def mock_server_config() -> dict:
    """Provide mock server configuration.

    Returns:
        Dictionary with server configuration
    """
    return {
        "host": "localhost",
        "port": 50051,
        "timeout": 30,
        "max_retries": 3,
    }


@pytest.fixture
def agent_states() -> dict:
    """Track agent states for workflow tests.

    Returns:
        Dictionary mapping agent_id to state information
    """
    return {}


@pytest.fixture
def task_registry() -> dict:
    """Track submitted tasks for workflow tests.

    Returns:
        Dictionary mapping task_id to task information
    """
    return {}
