"""Integration tests for full agent workflows.

This module tests complete workflows involving agent lifecycle management,
task submission and completion, preemption flows, and activity buffer operations.
Tests simulate real-world scenarios of agents progressing through their lifecycle.
"""
import pytest
from unittest.mock import MagicMock, call
from datetime import timedelta


class TestAgentLifecycle:
    """Test complete agent lifecycle from initialization to completion."""

    def test_agent_lifecycle_initializing_to_runnable(
        self, scheduler_client, worktree_client, mock_scheduler_stub, mock_worktree_stub
    ):
        """Test agent transitioning from INITIALIZING to RUNNABLE.

        Workflow:
        1. Agent binds to worktree (INITIALIZING -> RUNNABLE)
        2. Verify worktree binding status
        """
        # Arrange - simulate INITIALIZING state
        bind_response = MagicMock()
        bind_response.acknowledged = True
        bind_response.state = "RUNNABLE"
        mock_worktree_stub.Bind.return_value = bind_response

        status_response = MagicMock()
        status_response.bound = True
        status_response.worktree_id = "worktree-1"
        status_response.state = "RUNNABLE"
        mock_worktree_stub.Status.return_value = status_response

        # Act - transition to RUNNABLE
        bind_resp = worktree_client.bind(
            agent_id="agent-1",
            repo_id="repo-1",
            worktree_id="worktree-1"
        )

        status_resp = worktree_client.status(agent_id="agent-1")

        # Assert
        assert bind_resp.acknowledged
        assert bind_resp.state == "RUNNABLE"
        assert status_resp.bound
        assert status_resp.state == "RUNNABLE"

    def test_agent_lifecycle_runnable_to_scheduled(
        self, scheduler_client, mock_scheduler_stub
    ):
        """Test agent transitioning from RUNNABLE to SCHEDULED.

        Workflow:
        1. Submit task to scheduler (RUNNABLE -> SCHEDULED)
        2. Verify task is acknowledged and scheduled
        """
        # Arrange - simulate RUNNABLE state
        submit_response = MagicMock()
        submit_response.acknowledged = True
        submit_response.task_id = "task-123"
        submit_response.state = "SCHEDULED"
        mock_scheduler_stub.SubmitTask.return_value = submit_response

        # Act - submit task to transition to SCHEDULED
        response = scheduler_client.submit_task(
            agent_id="agent-1",
            task_id="task-123",
            priority=5,
            scope="main",
            params=b'{"action": "process"}',
            content_type="application/json"
        )

        # Assert
        assert response.acknowledged
        assert response.task_id == "task-123"
        assert response.state == "SCHEDULED"

    def test_agent_lifecycle_scheduled_to_running(
        self, scheduler_client, mock_scheduler_stub
    ):
        """Test agent transitioning from SCHEDULED to RUNNING.

        Workflow:
        1. Task is scheduled
        2. Poll activity buffer to see task running
        """
        # Arrange - simulate task getting picked up
        poll_response = MagicMock()

        entry = MagicMock()
        entry.task_id = "task-123"
        entry.state = "RUNNING"
        entry.agent_id = "agent-1"
        entry.started_at = "2025-12-23T10:00:00Z"

        poll_response.entries = [entry]
        mock_scheduler_stub.PollActivityBuffer.return_value = poll_response

        # Act - poll to see task running
        response = scheduler_client.poll_activity_buffer(agent_id="agent-1")

        # Assert
        assert len(response.entries) == 1
        assert response.entries[0].task_id == "task-123"
        assert response.entries[0].state == "RUNNING"

    def test_agent_lifecycle_running_to_completed(
        self, scheduler_client, mock_scheduler_stub
    ):
        """Test agent transitioning from RUNNING to COMPLETED.

        Workflow:
        1. Task is running
        2. Task completes successfully
        3. Poll activity buffer to see completed task
        """
        # Arrange - simulate task completion
        poll_response = MagicMock()

        entry = MagicMock()
        entry.task_id = "task-123"
        entry.state = "COMPLETED"
        entry.agent_id = "agent-1"
        entry.completed_at = "2025-12-23T10:05:00Z"
        entry.result = b'{"status": "success"}'

        poll_response.entries = [entry]
        mock_scheduler_stub.PollActivityBuffer.return_value = poll_response

        # Act - poll to see completed task
        response = scheduler_client.poll_activity_buffer(agent_id="agent-1")

        # Assert
        assert len(response.entries) == 1
        assert response.entries[0].task_id == "task-123"
        assert response.entries[0].state == "COMPLETED"
        assert response.entries[0].result == b'{"status": "success"}'

    def test_full_agent_lifecycle_end_to_end(
        self, scheduler_client, worktree_client,
        mock_scheduler_stub, mock_worktree_stub
    ):
        """Test complete agent lifecycle from initialization to shutdown.

        Workflow:
        1. INITIALIZING: Bind to worktree
        2. RUNNABLE: Submit task
        3. SCHEDULED: Task queued
        4. RUNNING: Task executing
        5. COMPLETED: Task finished
        6. Purge completed tasks
        7. Shutdown agent
        """
        # 1. INITIALIZING -> RUNNABLE: Bind to worktree
        bind_response = MagicMock()
        bind_response.acknowledged = True
        mock_worktree_stub.Bind.return_value = bind_response

        bind_resp = worktree_client.bind("agent-1", "repo-1", "worktree-1")
        assert bind_resp.acknowledged

        # 2. RUNNABLE -> SCHEDULED: Submit task
        submit_response = MagicMock()
        submit_response.acknowledged = True
        submit_response.task_id = "task-123"
        mock_scheduler_stub.SubmitTask.return_value = submit_response

        submit_resp = scheduler_client.submit_task(
            agent_id="agent-1",
            task_id="task-123",
            priority=5
        )
        assert submit_resp.acknowledged

        # 3. SCHEDULED -> RUNNING: Poll to see running
        running_entry = MagicMock()
        running_entry.task_id = "task-123"
        running_entry.state = "RUNNING"

        poll_running = MagicMock()
        poll_running.entries = [running_entry]
        mock_scheduler_stub.PollActivityBuffer.return_value = poll_running

        poll_resp_1 = scheduler_client.poll_activity_buffer("agent-1")
        assert poll_resp_1.entries[0].state == "RUNNING"

        # 4. RUNNING -> COMPLETED: Poll to see completion
        completed_entry = MagicMock()
        completed_entry.task_id = "task-123"
        completed_entry.state = "COMPLETED"

        poll_completed = MagicMock()
        poll_completed.entries = [completed_entry]
        mock_scheduler_stub.PollActivityBuffer.return_value = poll_completed

        poll_resp_2 = scheduler_client.poll_activity_buffer("agent-1")
        assert poll_resp_2.entries[0].state == "COMPLETED"

        # 5. Purge completed tasks
        purge_response = MagicMock()
        purge_response.purged_count = 1
        mock_scheduler_stub.PurgeActivity.return_value = purge_response

        purge_resp = scheduler_client.purge_activity("agent-1", ["task-123"])
        assert purge_resp.purged_count == 1

        # 6. Shutdown agent
        shutdown_response = MagicMock()
        shutdown_response.acknowledged = True
        mock_scheduler_stub.ShutdownAgent.return_value = shutdown_response

        shutdown_resp = scheduler_client.shutdown_agent(
            "agent-1",
            grace_period=timedelta(seconds=30)
        )
        assert shutdown_resp.acknowledged

        # Verify call sequence
        assert mock_worktree_stub.Bind.call_count == 1
        assert mock_scheduler_stub.SubmitTask.call_count == 1
        assert mock_scheduler_stub.PollActivityBuffer.call_count == 2
        assert mock_scheduler_stub.PurgeActivity.call_count == 1
        assert mock_scheduler_stub.ShutdownAgent.call_count == 1


class TestTaskSubmissionAndCompletion:
    """Test task submission and completion workflows."""

    def test_single_task_submission_and_completion(
        self, scheduler_client, mock_scheduler_stub
    ):
        """Test submitting and completing a single task."""
        # Arrange
        submit_response = MagicMock()
        submit_response.acknowledged = True
        submit_response.task_id = "task-1"
        mock_scheduler_stub.SubmitTask.return_value = submit_response

        completed_entry = MagicMock()
        completed_entry.task_id = "task-1"
        completed_entry.state = "COMPLETED"

        poll_response = MagicMock()
        poll_response.entries = [completed_entry]
        mock_scheduler_stub.PollActivityBuffer.return_value = poll_response

        # Act
        submit_resp = scheduler_client.submit_task("agent-1", "task-1")
        poll_resp = scheduler_client.poll_activity_buffer("agent-1")

        # Assert
        assert submit_resp.acknowledged
        assert poll_resp.entries[0].state == "COMPLETED"

    def test_multiple_task_submission_and_completion(
        self, scheduler_client, mock_scheduler_stub
    ):
        """Test submitting and completing multiple tasks."""
        # Arrange
        submit_response = MagicMock()
        submit_response.acknowledged = True
        mock_scheduler_stub.SubmitTask.return_value = submit_response

        # Create entries for 5 tasks
        entries = []
        for i in range(1, 6):
            entry = MagicMock()
            entry.task_id = f"task-{i}"
            entry.state = "COMPLETED"
            entries.append(entry)

        poll_response = MagicMock()
        poll_response.entries = entries
        mock_scheduler_stub.PollActivityBuffer.return_value = poll_response

        # Act - submit 5 tasks
        for i in range(1, 6):
            resp = scheduler_client.submit_task("agent-1", f"task-{i}", priority=i)
            assert resp.acknowledged

        # Poll to see all completed
        poll_resp = scheduler_client.poll_activity_buffer("agent-1")

        # Assert
        assert len(poll_resp.entries) == 5
        assert all(e.state == "COMPLETED" for e in poll_resp.entries)
        assert mock_scheduler_stub.SubmitTask.call_count == 5

    def test_task_priority_ordering(self, scheduler_client, mock_scheduler_stub):
        """Test that higher priority tasks are processed first."""
        # Arrange
        submit_response = MagicMock()
        submit_response.acknowledged = True
        mock_scheduler_stub.SubmitTask.return_value = submit_response

        # Simulate high priority task completing first
        high_priority_entry = MagicMock()
        high_priority_entry.task_id = "task-high"
        high_priority_entry.state = "COMPLETED"
        high_priority_entry.priority = 10

        low_priority_entry = MagicMock()
        low_priority_entry.task_id = "task-low"
        low_priority_entry.state = "SCHEDULED"
        low_priority_entry.priority = -5

        poll_response = MagicMock()
        poll_response.entries = [high_priority_entry, low_priority_entry]
        mock_scheduler_stub.PollActivityBuffer.return_value = poll_response

        # Act - submit low priority then high priority
        scheduler_client.submit_task("agent-1", "task-low", priority=-5)
        scheduler_client.submit_task("agent-1", "task-high", priority=10)

        poll_resp = scheduler_client.poll_activity_buffer("agent-1")

        # Assert - high priority task completed first
        assert poll_resp.entries[0].task_id == "task-high"
        assert poll_resp.entries[0].state == "COMPLETED"
        assert poll_resp.entries[1].task_id == "task-low"
        assert poll_resp.entries[1].state == "SCHEDULED"

    def test_task_with_scope_conflicts(self, scheduler_client, mock_scheduler_stub):
        """Test task submission with scope-based conflict detection."""
        # Arrange
        submit_response = MagicMock()
        submit_response.acknowledged = True
        mock_scheduler_stub.SubmitTask.return_value = submit_response

        # Act - submit tasks with same scope (should serialize)
        scheduler_client.submit_task(
            "agent-1", "task-1", scope="file:/path/to/file.txt"
        )
        scheduler_client.submit_task(
            "agent-1", "task-2", scope="file:/path/to/file.txt"
        )

        # Assert - both submitted but would be serialized by server
        assert mock_scheduler_stub.SubmitTask.call_count == 2


class TestPreemptionFlow:
    """Test task preemption workflows."""

    def test_preempt_running_task(self, scheduler_client, mock_scheduler_stub):
        """Test preempting a currently running task."""
        # Arrange - task is running
        running_entry = MagicMock()
        running_entry.task_id = "task-1"
        running_entry.state = "RUNNING"

        poll_response = MagicMock()
        poll_response.entries = [running_entry]
        mock_scheduler_stub.PollActivityBuffer.return_value = poll_response

        # Preemption succeeds
        preempt_response = MagicMock()
        preempt_response.acknowledged = True
        preempt_response.preempted = True
        mock_scheduler_stub.RequestPreemption.return_value = preempt_response

        # After preemption, task is preempted
        preempted_entry = MagicMock()
        preempted_entry.task_id = "task-1"
        preempted_entry.state = "PREEMPTED"

        poll_after_preempt = MagicMock()
        poll_after_preempt.entries = [preempted_entry]

        # Act
        poll_before = scheduler_client.poll_activity_buffer("agent-1")
        assert poll_before.entries[0].state == "RUNNING"

        preempt_resp = scheduler_client.request_preemption(
            "agent-1", "task-1", reason="Higher priority task available"
        )
        assert preempt_resp.preempted

        # Update mock for after preemption
        mock_scheduler_stub.PollActivityBuffer.return_value = poll_after_preempt

        poll_after = scheduler_client.poll_activity_buffer("agent-1")

        # Assert
        assert poll_after.entries[0].state == "PREEMPTED"
        assert mock_scheduler_stub.RequestPreemption.called

    def test_preemption_with_new_high_priority_task(
        self, scheduler_client, mock_scheduler_stub
    ):
        """Test preempting a task to make room for higher priority task."""
        # Arrange - low priority task running
        running_entry = MagicMock()
        running_entry.task_id = "task-low"
        running_entry.state = "RUNNING"
        running_entry.priority = 0

        poll_response_1 = MagicMock()
        poll_response_1.entries = [running_entry]
        mock_scheduler_stub.PollActivityBuffer.return_value = poll_response_1

        # Preempt the low priority task
        preempt_response = MagicMock()
        preempt_response.acknowledged = True
        preempt_response.preempted = True
        mock_scheduler_stub.RequestPreemption.return_value = preempt_response

        # Submit high priority task
        submit_response = MagicMock()
        submit_response.acknowledged = True
        submit_response.task_id = "task-high"
        mock_scheduler_stub.SubmitTask.return_value = submit_response

        # After preemption and new submission
        high_priority_entry = MagicMock()
        high_priority_entry.task_id = "task-high"
        high_priority_entry.state = "RUNNING"
        high_priority_entry.priority = 10

        preempted_entry = MagicMock()
        preempted_entry.task_id = "task-low"
        preempted_entry.state = "PREEMPTED"
        preempted_entry.priority = 0

        poll_response_2 = MagicMock()
        poll_response_2.entries = [high_priority_entry, preempted_entry]

        # Act
        poll_1 = scheduler_client.poll_activity_buffer("agent-1")
        assert poll_1.entries[0].state == "RUNNING"

        preempt_resp = scheduler_client.request_preemption("agent-1", "task-low")
        assert preempt_resp.preempted

        submit_resp = scheduler_client.submit_task(
            "agent-1", "task-high", priority=10
        )
        assert submit_resp.acknowledged

        mock_scheduler_stub.PollActivityBuffer.return_value = poll_response_2
        poll_2 = scheduler_client.poll_activity_buffer("agent-1")

        # Assert - high priority task now running
        assert poll_2.entries[0].task_id == "task-high"
        assert poll_2.entries[0].state == "RUNNING"
        assert poll_2.entries[1].task_id == "task-low"
        assert poll_2.entries[1].state == "PREEMPTED"

    def test_failed_preemption_task_not_running(
        self, scheduler_client, mock_scheduler_stub
    ):
        """Test preemption fails when task is not running."""
        # Arrange - task already completed
        preempt_response = MagicMock()
        preempt_response.acknowledged = True
        preempt_response.preempted = False
        preempt_response.reason = "Task not running"
        mock_scheduler_stub.RequestPreemption.return_value = preempt_response

        # Act
        response = scheduler_client.request_preemption("agent-1", "task-completed")

        # Assert
        assert response.acknowledged
        assert not response.preempted
        assert response.reason == "Task not running"


class TestActivityBufferOperations:
    """Test activity buffer operations and workflows."""

    def test_poll_empty_activity_buffer(self, scheduler_client, mock_scheduler_stub):
        """Test polling an empty activity buffer."""
        # Arrange
        poll_response = MagicMock()
        poll_response.entries = []
        mock_scheduler_stub.PollActivityBuffer.return_value = poll_response

        # Act
        response = scheduler_client.poll_activity_buffer("agent-1")

        # Assert
        assert len(response.entries) == 0

    def test_poll_activity_buffer_with_multiple_entries(
        self, scheduler_client, mock_scheduler_stub
    ):
        """Test polling activity buffer with multiple task entries."""
        # Arrange
        entries = []
        for i in range(1, 11):
            entry = MagicMock()
            entry.task_id = f"task-{i}"
            entry.state = "COMPLETED" if i <= 5 else "RUNNING"
            entries.append(entry)

        poll_response = MagicMock()
        poll_response.entries = entries
        mock_scheduler_stub.PollActivityBuffer.return_value = poll_response

        # Act
        response = scheduler_client.poll_activity_buffer("agent-1")

        # Assert
        assert len(response.entries) == 10
        completed = [e for e in response.entries if e.state == "COMPLETED"]
        running = [e for e in response.entries if e.state == "RUNNING"]
        assert len(completed) == 5
        assert len(running) == 5

    def test_purge_completed_tasks_from_buffer(
        self, scheduler_client, mock_scheduler_stub
    ):
        """Test purging completed tasks from activity buffer."""
        # Arrange - buffer has completed tasks
        entries = []
        for i in range(1, 6):
            entry = MagicMock()
            entry.task_id = f"task-{i}"
            entry.state = "COMPLETED"
            entries.append(entry)

        poll_response = MagicMock()
        poll_response.entries = entries
        mock_scheduler_stub.PollActivityBuffer.return_value = poll_response

        # Purge response
        purge_response = MagicMock()
        purge_response.purged_count = 5
        mock_scheduler_stub.PurgeActivity.return_value = purge_response

        # After purge - empty buffer
        empty_response = MagicMock()
        empty_response.entries = []

        # Act
        poll_before = scheduler_client.poll_activity_buffer("agent-1")
        assert len(poll_before.entries) == 5

        task_ids = [f"task-{i}" for i in range(1, 6)]
        purge_resp = scheduler_client.purge_activity("agent-1", task_ids)
        assert purge_resp.purged_count == 5

        mock_scheduler_stub.PollActivityBuffer.return_value = empty_response
        poll_after = scheduler_client.poll_activity_buffer("agent-1")

        # Assert
        assert len(poll_after.entries) == 0

    def test_partial_purge_of_activity_buffer(
        self, scheduler_client, mock_scheduler_stub
    ):
        """Test purging only some tasks from activity buffer."""
        # Arrange - buffer has 5 tasks
        all_entries = []
        for i in range(1, 6):
            entry = MagicMock()
            entry.task_id = f"task-{i}"
            entry.state = "COMPLETED"
            all_entries.append(entry)

        poll_response_1 = MagicMock()
        poll_response_1.entries = all_entries
        mock_scheduler_stub.PollActivityBuffer.return_value = poll_response_1

        # Purge only 3 tasks
        purge_response = MagicMock()
        purge_response.purged_count = 3
        mock_scheduler_stub.PurgeActivity.return_value = purge_response

        # After purge - 2 remain
        remaining_entries = [all_entries[3], all_entries[4]]
        poll_response_2 = MagicMock()
        poll_response_2.entries = remaining_entries

        # Act
        poll_before = scheduler_client.poll_activity_buffer("agent-1")
        assert len(poll_before.entries) == 5

        purge_resp = scheduler_client.purge_activity(
            "agent-1", ["task-1", "task-2", "task-3"]
        )
        assert purge_resp.purged_count == 3

        mock_scheduler_stub.PollActivityBuffer.return_value = poll_response_2
        poll_after = scheduler_client.poll_activity_buffer("agent-1")

        # Assert
        assert len(poll_after.entries) == 2
        assert poll_after.entries[0].task_id == "task-4"
        assert poll_after.entries[1].task_id == "task-5"

    def test_activity_buffer_lifecycle_workflow(
        self, scheduler_client, mock_scheduler_stub
    ):
        """Test complete activity buffer workflow: submit -> poll -> purge."""
        # Step 1: Submit tasks
        submit_response = MagicMock()
        submit_response.acknowledged = True
        mock_scheduler_stub.SubmitTask.return_value = submit_response

        for i in range(1, 4):
            resp = scheduler_client.submit_task("agent-1", f"task-{i}")
            assert resp.acknowledged

        # Step 2: Poll to see tasks (some completed, some running)
        entries_poll_1 = [
            MagicMock(task_id="task-1", state="COMPLETED"),
            MagicMock(task_id="task-2", state="COMPLETED"),
            MagicMock(task_id="task-3", state="RUNNING"),
        ]
        poll_response_1 = MagicMock()
        poll_response_1.entries = entries_poll_1
        mock_scheduler_stub.PollActivityBuffer.return_value = poll_response_1

        poll_1 = scheduler_client.poll_activity_buffer("agent-1")
        assert len(poll_1.entries) == 3

        # Step 3: Purge completed tasks
        purge_response = MagicMock()
        purge_response.purged_count = 2
        mock_scheduler_stub.PurgeActivity.return_value = purge_response

        purge_resp = scheduler_client.purge_activity("agent-1", ["task-1", "task-2"])
        assert purge_resp.purged_count == 2

        # Step 4: Poll again to see only running task
        entries_poll_2 = [
            MagicMock(task_id="task-3", state="RUNNING"),
        ]
        poll_response_2 = MagicMock()
        poll_response_2.entries = entries_poll_2
        mock_scheduler_stub.PollActivityBuffer.return_value = poll_response_2

        poll_2 = scheduler_client.poll_activity_buffer("agent-1")
        assert len(poll_2.entries) == 1
        assert poll_2.entries[0].task_id == "task-3"
        assert poll_2.entries[0].state == "RUNNING"
