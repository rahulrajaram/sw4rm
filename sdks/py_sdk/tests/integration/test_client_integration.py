"""Integration tests for SW4RM Protocol clients.

This module tests the integration of client classes with mock gRPC servers,
verifying that clients correctly communicate with the server and handle
responses and errors appropriately.
"""
import pytest
import grpc
from unittest.mock import MagicMock, patch
from datetime import timedelta


class TestSchedulerClientIntegration:
    """Integration tests for SchedulerClient with mock server."""

    def test_submit_task_integration(self, scheduler_client, mock_scheduler_stub):
        """Test task submission through the client."""
        # Arrange
        mock_response = MagicMock()
        mock_response.acknowledged = True
        mock_response.task_id = "task-123"
        mock_scheduler_stub.SubmitTask.return_value = mock_response

        # Act
        response = scheduler_client.submit_task(
            agent_id="agent-1",
            task_id="task-123",
            priority=5,
            scope="test-scope",
            params=b'{"action": "test"}',
            content_type="application/json"
        )

        # Assert
        assert mock_scheduler_stub.SubmitTask.called
        assert response.acknowledged is True
        assert response.task_id == "task-123"

    def test_submit_multiple_tasks_integration(self, scheduler_client, mock_scheduler_stub):
        """Test submitting multiple tasks in sequence."""
        # Arrange
        mock_response = MagicMock()
        mock_response.acknowledged = True
        mock_scheduler_stub.SubmitTask.return_value = mock_response

        task_ids = [f"task-{i}" for i in range(10)]

        # Act
        for task_id in task_ids:
            response = scheduler_client.submit_task(
                agent_id="agent-1",
                task_id=task_id,
                priority=0
            )
            assert response.acknowledged is True

        # Assert
        assert mock_scheduler_stub.SubmitTask.call_count == 10

    def test_poll_activity_buffer_integration(self, scheduler_client, mock_scheduler_stub):
        """Test polling activity buffer."""
        # Arrange
        mock_entry_1 = MagicMock()
        mock_entry_1.task_id = "task-1"
        mock_entry_1.state = "COMPLETED"

        mock_entry_2 = MagicMock()
        mock_entry_2.task_id = "task-2"
        mock_entry_2.state = "RUNNING"

        mock_response = MagicMock()
        mock_response.entries = [mock_entry_1, mock_entry_2]
        mock_scheduler_stub.PollActivityBuffer.return_value = mock_response

        # Act
        response = scheduler_client.poll_activity_buffer(agent_id="agent-1")

        # Assert
        assert len(response.entries) == 2
        assert response.entries[0].task_id == "task-1"
        assert response.entries[0].state == "COMPLETED"
        assert response.entries[1].task_id == "task-2"
        assert response.entries[1].state == "RUNNING"

    def test_request_preemption_integration(self, scheduler_client, mock_scheduler_stub):
        """Test requesting task preemption."""
        # Arrange
        mock_response = MagicMock()
        mock_response.acknowledged = True
        mock_response.preempted = True
        mock_scheduler_stub.RequestPreemption.return_value = mock_response

        # Act
        response = scheduler_client.request_preemption(
            agent_id="agent-1",
            task_id="task-123",
            reason="Higher priority task available"
        )

        # Assert
        assert response.acknowledged is True
        assert response.preempted is True
        assert mock_scheduler_stub.RequestPreemption.called

    def test_purge_activity_integration(self, scheduler_client, mock_scheduler_stub):
        """Test purging completed tasks from activity buffer."""
        # Arrange
        mock_response = MagicMock()
        mock_response.purged_count = 3
        mock_scheduler_stub.PurgeActivity.return_value = mock_response

        task_ids = ["task-1", "task-2", "task-3"]

        # Act
        response = scheduler_client.purge_activity(agent_id="agent-1", task_ids=task_ids)

        # Assert
        assert response.purged_count == 3
        assert mock_scheduler_stub.PurgeActivity.called

    def test_shutdown_agent_integration(self, scheduler_client, mock_scheduler_stub):
        """Test agent shutdown request."""
        # Arrange
        mock_response = MagicMock()
        mock_response.acknowledged = True
        mock_scheduler_stub.ShutdownAgent.return_value = mock_response

        # Act
        response = scheduler_client.shutdown_agent(
            agent_id="agent-1",
            grace_period=timedelta(seconds=30)
        )

        # Assert
        assert response.acknowledged is True
        assert mock_scheduler_stub.ShutdownAgent.called

    def test_scheduler_grpc_error_handling(self, scheduler_client, mock_scheduler_stub):
        """Test handling of gRPC errors."""
        # Arrange
        mock_scheduler_stub.SubmitTask.side_effect = grpc.RpcError()

        # Act & Assert
        with pytest.raises(grpc.RpcError):
            scheduler_client.submit_task(agent_id="agent-1", task_id="task-1")

    def test_scheduler_timeout_handling(self, scheduler_client, mock_scheduler_stub):
        """Test handling of timeout errors."""
        # Arrange
        timeout_error = grpc.RpcError()
        timeout_error.code = lambda: grpc.StatusCode.DEADLINE_EXCEEDED
        mock_scheduler_stub.SubmitTask.side_effect = timeout_error

        # Act & Assert
        with pytest.raises(grpc.RpcError):
            scheduler_client.submit_task(agent_id="agent-1", task_id="task-1")


class TestWorktreeClientIntegration:
    """Integration tests for WorktreeClient with mock server."""

    def test_bind_worktree_integration(self, worktree_client, mock_worktree_stub):
        """Test binding an agent to a worktree."""
        # Arrange
        mock_response = MagicMock()
        mock_response.acknowledged = True
        mock_worktree_stub.Bind.return_value = mock_response

        # Act
        response = worktree_client.bind(
            agent_id="agent-1",
            repo_id="repo-1",
            worktree_id="worktree-1"
        )

        # Assert
        assert response.acknowledged is True
        assert mock_worktree_stub.Bind.called

    def test_unbind_worktree_integration(self, worktree_client, mock_worktree_stub):
        """Test unbinding an agent from a worktree."""
        # Arrange
        mock_response = MagicMock()
        mock_response.acknowledged = True
        mock_worktree_stub.Unbind.return_value = mock_response

        # Act
        response = worktree_client.unbind(agent_id="agent-1")

        # Assert
        assert response.acknowledged is True
        assert mock_worktree_stub.Unbind.called

    def test_worktree_status_integration(self, worktree_client, mock_worktree_stub):
        """Test querying worktree status."""
        # Arrange
        mock_response = MagicMock()
        mock_response.worktree_id = "worktree-1"
        mock_response.repo_id = "repo-1"
        mock_response.bound = True
        mock_response.branch = "main"
        mock_worktree_stub.Status.return_value = mock_response

        # Act
        response = worktree_client.status(agent_id="agent-1")

        # Assert
        assert response.worktree_id == "worktree-1"
        assert response.repo_id == "repo-1"
        assert response.bound is True
        assert response.branch == "main"

    def test_request_switch_integration(self, worktree_client, mock_worktree_stub):
        """Test requesting a worktree switch."""
        # Arrange
        mock_response = MagicMock()
        mock_response.acknowledged = True
        mock_worktree_stub.RequestSwitch.return_value = mock_response

        # Act
        response = worktree_client.request_switch(
            agent_id="agent-1",
            target_worktree_id="worktree-2",
            requires_hitl=True
        )

        # Assert
        assert response.acknowledged is True
        assert mock_worktree_stub.RequestSwitch.called

    def test_approve_switch_integration(self, worktree_client, mock_worktree_stub):
        """Test approving a worktree switch."""
        # Arrange
        mock_response = MagicMock()
        mock_response.acknowledged = True
        mock_worktree_stub.ApproveSwitch.return_value = mock_response

        # Act
        response = worktree_client.approve_switch(
            agent_id="agent-1",
            target_worktree_id="worktree-2",
            ttl_ms=60000
        )

        # Assert
        assert response.acknowledged is True
        assert mock_worktree_stub.ApproveSwitch.called

    def test_reject_switch_integration(self, worktree_client, mock_worktree_stub):
        """Test rejecting a worktree switch."""
        # Arrange
        mock_response = MagicMock()
        mock_response.acknowledged = True
        mock_worktree_stub.RejectSwitch.return_value = mock_response

        # Act
        response = worktree_client.reject_switch(
            agent_id="agent-1",
            reason="Conflicts detected"
        )

        # Assert
        assert response.acknowledged is True
        assert mock_worktree_stub.RejectSwitch.called

    def test_worktree_full_lifecycle_integration(self, worktree_client, mock_worktree_stub):
        """Test full worktree lifecycle: bind -> status -> switch -> unbind."""
        # Arrange - configure responses
        bind_response = MagicMock()
        bind_response.acknowledged = True
        mock_worktree_stub.Bind.return_value = bind_response

        status_response = MagicMock()
        status_response.bound = True
        status_response.worktree_id = "worktree-1"
        mock_worktree_stub.Status.return_value = status_response

        switch_response = MagicMock()
        switch_response.acknowledged = True
        mock_worktree_stub.RequestSwitch.return_value = switch_response

        approve_response = MagicMock()
        approve_response.acknowledged = True
        mock_worktree_stub.ApproveSwitch.return_value = approve_response

        unbind_response = MagicMock()
        unbind_response.acknowledged = True
        mock_worktree_stub.Unbind.return_value = unbind_response

        # Act - execute lifecycle
        bind_resp = worktree_client.bind("agent-1", "repo-1", "worktree-1")
        assert bind_resp.acknowledged

        status_resp = worktree_client.status("agent-1")
        assert status_resp.bound

        switch_req = worktree_client.request_switch("agent-1", "worktree-2")
        assert switch_req.acknowledged

        approve_resp = worktree_client.approve_switch("agent-1", "worktree-2", ttl_ms=30000)
        assert approve_resp.acknowledged

        unbind_resp = worktree_client.unbind("agent-1")
        assert unbind_resp.acknowledged

        # Assert - verify call sequence
        assert mock_worktree_stub.Bind.call_count == 1
        assert mock_worktree_stub.Status.call_count == 1
        assert mock_worktree_stub.RequestSwitch.call_count == 1
        assert mock_worktree_stub.ApproveSwitch.call_count == 1
        assert mock_worktree_stub.Unbind.call_count == 1


class TestToolClientIntegration:
    """Integration tests for ToolClient with mock server."""

    def test_tool_call_integration(self, tool_client, mock_tool_stub):
        """Test executing a unary tool call."""
        # Arrange
        mock_response = MagicMock()
        mock_response.result = b'{"output": "success"}'
        mock_response.content_type = "application/json"
        mock_tool_stub.Call.return_value = mock_response

        call_params = {
            "call_id": "call-123",
            "tool_name": "calculator",
            "provider_id": "default",
            "args": b'{"operation": "add", "a": 1, "b": 2}'
        }

        # Act
        response = tool_client.call(call_params)

        # Assert
        assert response.result == b'{"output": "success"}'
        assert response.content_type == "application/json"
        assert mock_tool_stub.Call.called

    def test_tool_call_stream_integration(self, tool_client, mock_tool_stub):
        """Test executing a streaming tool call."""
        # Arrange
        stream_frames = [
            MagicMock(chunk=b'{"partial": 1}'),
            MagicMock(chunk=b'{"partial": 2}'),
            MagicMock(chunk=b'{"partial": 3}'),
        ]
        mock_tool_stub.CallStream.return_value = iter(stream_frames)

        call_params = {
            "call_id": "call-456",
            "tool_name": "stream_processor",
            "provider_id": "default",
            "args": b'{}'
        }

        # Act
        responses = list(tool_client.call_stream(call_params))

        # Assert
        assert len(responses) == 3
        assert responses[0].chunk == b'{"partial": 1}'
        assert responses[2].chunk == b'{"partial": 3}'
        assert mock_tool_stub.CallStream.called

    def test_tool_cancel_integration(self, tool_client, mock_tool_stub):
        """Test canceling a tool call."""
        # Arrange
        mock_response = MagicMock()
        mock_response.acknowledged = True
        mock_tool_stub.Cancel.return_value = mock_response

        call_params = {
            "call_id": "call-789"
        }

        # Act
        response = tool_client.cancel(call_params)

        # Assert
        assert response.acknowledged is True
        assert mock_tool_stub.Cancel.called

    def test_tool_error_handling(self, tool_client, mock_tool_stub):
        """Test handling tool execution errors."""
        # Arrange
        mock_tool_stub.Call.side_effect = grpc.RpcError()

        call_params = {
            "call_id": "call-error",
            "tool_name": "failing_tool",
            "provider_id": "default"
        }

        # Act & Assert
        with pytest.raises(grpc.RpcError):
            tool_client.call(call_params)


class TestNegotiationClientIntegration:
    """Integration tests for NegotiationClient with mock server."""

    def test_open_negotiation_integration(self, negotiation_client, mock_negotiation_stub):
        """Test opening a negotiation."""
        # Arrange
        mock_response = MagicMock()
        mock_response.acknowledged = True
        mock_negotiation_stub.Open.return_value = mock_response

        # Act
        response = negotiation_client.open(
            negotiation_id="neg-123",
            correlation_id="corr-456",
            topic="Resource allocation",
            participants=["agent-1", "agent-2"],
            intensity=5
        )

        # Assert
        assert response.acknowledged is True
        assert mock_negotiation_stub.Open.called

    def test_propose_integration(self, negotiation_client, mock_negotiation_stub):
        """Test submitting a proposal."""
        # Arrange
        mock_response = MagicMock()
        mock_response.acknowledged = True
        mock_negotiation_stub.Propose.return_value = mock_response

        # Act
        response = negotiation_client.propose(
            negotiation_id="neg-123",
            from_agent="agent-1",
            content_type="application/json",
            payload=b'{"proposal": "allocate_resource_1"}'
        )

        # Assert
        assert response.acknowledged is True
        assert mock_negotiation_stub.Propose.called

    def test_counter_integration(self, negotiation_client, mock_negotiation_stub):
        """Test submitting a counter-proposal."""
        # Arrange
        mock_response = MagicMock()
        mock_response.acknowledged = True
        mock_negotiation_stub.Counter.return_value = mock_response

        # Act
        response = negotiation_client.counter(
            negotiation_id="neg-123",
            from_agent="agent-2",
            content_type="application/json",
            payload=b'{"counter": "allocate_resource_2"}'
        )

        # Assert
        assert response.acknowledged is True
        assert mock_negotiation_stub.Counter.called

    def test_evaluate_integration(self, negotiation_client, mock_negotiation_stub):
        """Test evaluating a proposal."""
        # Arrange
        mock_response = MagicMock()
        mock_response.acknowledged = True
        mock_negotiation_stub.Evaluate.return_value = mock_response

        # Act
        response = negotiation_client.evaluate(
            negotiation_id="neg-123",
            from_agent="agent-3",
            confidence_score=0.85,
            notes="Proposal is acceptable"
        )

        # Assert
        assert response.acknowledged is True
        assert mock_negotiation_stub.Evaluate.called

    def test_decide_integration(self, negotiation_client, mock_negotiation_stub):
        """Test making a final decision."""
        # Arrange
        mock_response = MagicMock()
        mock_response.acknowledged = True
        mock_negotiation_stub.Decide.return_value = mock_response

        # Act
        response = negotiation_client.decide(
            negotiation_id="neg-123",
            decided_by="agent-1",
            content_type="application/json",
            result=b'{"decision": "allocate_resource_1"}'
        )

        # Assert
        assert response.acknowledged is True
        assert mock_negotiation_stub.Decide.called

    def test_abort_integration(self, negotiation_client, mock_negotiation_stub):
        """Test aborting a negotiation."""
        # Arrange
        mock_response = MagicMock()
        mock_response.acknowledged = True
        mock_negotiation_stub.Abort.return_value = mock_response

        # Act
        response = negotiation_client.abort(
            negotiation_id="neg-123",
            reason="Timeout exceeded"
        )

        # Assert
        assert response.acknowledged is True
        assert mock_negotiation_stub.Abort.called


class TestActivityClientIntegration:
    """Integration tests for ActivityClient with mock server."""

    def test_append_artifact_integration(self, activity_client, mock_activity_stub):
        """Test appending an artifact."""
        # Arrange
        mock_response = MagicMock()
        mock_response.acknowledged = True
        mock_activity_stub.AppendArtifact.return_value = mock_response

        # Act
        response = activity_client.append_artifact(
            negotiation_id="neg-123",
            kind="spec",
            version="v1",
            content_type="application/json",
            content=b'{"spec": "data"}',
            created_at="2025-12-23T10:00:00Z"
        )

        # Assert
        assert response.acknowledged is True
        assert mock_activity_stub.AppendArtifact.called

    def test_list_artifacts_integration(self, activity_client, mock_activity_stub):
        """Test listing artifacts."""
        # Arrange
        mock_artifact_1 = MagicMock()
        mock_artifact_1.kind = "spec"
        mock_artifact_1.version = "v1"

        mock_artifact_2 = MagicMock()
        mock_artifact_2.kind = "code"
        mock_artifact_2.version = "v1"

        mock_response = MagicMock()
        mock_response.artifacts = [mock_artifact_1, mock_artifact_2]
        mock_activity_stub.ListArtifacts.return_value = mock_response

        # Act
        response = activity_client.list_artifacts(negotiation_id="neg-123")

        # Assert
        assert len(response.artifacts) == 2
        assert response.artifacts[0].kind == "spec"
        assert response.artifacts[1].kind == "code"
        assert mock_activity_stub.ListArtifacts.called

    def test_list_artifacts_filtered_integration(self, activity_client, mock_activity_stub):
        """Test listing artifacts filtered by kind."""
        # Arrange
        mock_artifact = MagicMock()
        mock_artifact.kind = "spec"
        mock_artifact.version = "v1"

        mock_response = MagicMock()
        mock_response.artifacts = [mock_artifact]
        mock_activity_stub.ListArtifacts.return_value = mock_response

        # Act
        response = activity_client.list_artifacts(negotiation_id="neg-123", kind="spec")

        # Assert
        assert len(response.artifacts) == 1
        assert response.artifacts[0].kind == "spec"
        assert mock_activity_stub.ListArtifacts.called


class TestCrossClientIntegration:
    """Integration tests involving multiple clients working together."""

    def test_scheduler_and_activity_integration(
        self, scheduler_client, activity_client, mock_scheduler_stub, mock_activity_stub
    ):
        """Test scheduler and activity clients working together."""
        # Arrange
        submit_response = MagicMock()
        submit_response.acknowledged = True
        mock_scheduler_stub.SubmitTask.return_value = submit_response

        append_response = MagicMock()
        append_response.acknowledged = True
        mock_activity_stub.AppendArtifact.return_value = append_response

        # Act - submit task and log artifact
        task_resp = scheduler_client.submit_task(
            agent_id="agent-1",
            task_id="task-123",
            priority=5
        )

        artifact_resp = activity_client.append_artifact(
            negotiation_id="neg-123",
            kind="task_result",
            version="v1",
            content_type="application/json",
            content=b'{"task_id": "task-123", "status": "completed"}',
            created_at="2025-12-23T10:00:00Z"
        )

        # Assert
        assert task_resp.acknowledged
        assert artifact_resp.acknowledged
        assert mock_scheduler_stub.SubmitTask.called
        assert mock_activity_stub.AppendArtifact.called

    def test_worktree_and_scheduler_integration(
        self, worktree_client, scheduler_client, mock_worktree_stub, mock_scheduler_stub
    ):
        """Test worktree and scheduler clients working together."""
        # Arrange
        bind_response = MagicMock()
        bind_response.acknowledged = True
        mock_worktree_stub.Bind.return_value = bind_response

        submit_response = MagicMock()
        submit_response.acknowledged = True
        mock_scheduler_stub.SubmitTask.return_value = submit_response

        # Act - bind worktree then submit task
        bind_resp = worktree_client.bind("agent-1", "repo-1", "worktree-1")
        task_resp = scheduler_client.submit_task("agent-1", "task-123")

        # Assert
        assert bind_resp.acknowledged
        assert task_resp.acknowledged
        assert mock_worktree_stub.Bind.called
        assert mock_scheduler_stub.SubmitTask.called
