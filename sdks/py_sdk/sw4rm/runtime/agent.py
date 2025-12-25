from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Optional, Iterable, ContextManager
import contextlib


# ---------------------------------------------------------------------------
# AgentState constants (12 states per spec section 8)
# These mirror the AgentState enum that will be in constants.py after Task 1.8
# ---------------------------------------------------------------------------
class AgentState:
    """Agent lifecycle state constants.

    The agent state machine defines 12 states that an agent can be in during
    its lifecycle. These states control what operations are valid and help
    coordinate scheduling, preemption, and recovery.
    """
    INITIALIZING = 0       # Agent is being initialized
    RUNNABLE = 1           # Agent is ready to be scheduled
    SCHEDULED = 2          # Agent has been assigned a task
    RUNNING = 3            # Agent is actively executing
    WAITING = 4            # Agent is waiting for external input/response
    WAITING_RESOURCES = 5  # Agent is waiting for resources to become available
    SUSPENDED = 6          # Agent execution has been suspended (preempted)
    RESUMED = 7            # Agent is resuming from suspension
    COMPLETED = 8          # Agent has completed its task successfully
    FAILED = 9             # Agent has failed
    SHUTTING_DOWN = 10     # Agent is in the process of shutting down
    RECOVERING = 11        # Agent is recovering from a failure

    # Human-readable names for logging/debugging
    _NAMES: dict[int, str] = {
        0: "INITIALIZING",
        1: "RUNNABLE",
        2: "SCHEDULED",
        3: "RUNNING",
        4: "WAITING",
        5: "WAITING_RESOURCES",
        6: "SUSPENDED",
        7: "RESUMED",
        8: "COMPLETED",
        9: "FAILED",
        10: "SHUTTING_DOWN",
        11: "RECOVERING",
    }

    @classmethod
    def name(cls, state: int) -> str:
        """Return the human-readable name for a state."""
        return cls._NAMES.get(state, f"UNKNOWN({state})")


class StateTransitionError(Exception):
    """Raised when an invalid state transition is attempted.

    This exception indicates that the requested state transition is not
    allowed according to the agent lifecycle state machine.
    """

    def __init__(
        self,
        current_state: int,
        target_state: int,
        message: Optional[str] = None
    ) -> None:
        """Initialize the exception.

        Args:
            current_state: The current state of the agent.
            target_state: The state that was attempted.
            message: Optional additional context message.
        """
        self.current_state = current_state
        self.target_state = target_state
        current_name = AgentState.name(current_state)
        target_name = AgentState.name(target_state)
        base_msg = f"Invalid state transition: {current_name} -> {target_name}"
        if message:
            base_msg = f"{base_msg}: {message}"
        super().__init__(base_msg)


@dataclass
class PreemptionState:
    requested: bool = False
    reason: str | None = None


class Agent:
    """Base Agent runtime skeleton with full lifecycle state machine.

    Subclass and implement the on_* hooks to handle messages and state changes.
    This skeleton does not open network connections; it is a scaffold
    for your business logic layered over the gRPC clients.

    The agent lifecycle follows a 12-state state machine (per spec section 8):

    States:
        - INITIALIZING: Agent is being set up
        - RUNNABLE: Agent is ready to be scheduled for work
        - SCHEDULED: Agent has been assigned a task
        - RUNNING: Agent is actively executing its task
        - WAITING: Agent is waiting for external input/response
        - WAITING_RESOURCES: Agent is waiting for resources
        - SUSPENDED: Agent has been preempted/suspended
        - RESUMED: Agent is resuming from suspension
        - COMPLETED: Agent finished successfully
        - FAILED: Agent encountered a failure
        - SHUTTING_DOWN: Agent is shutting down
        - RECOVERING: Agent is recovering from failure

    Example:
        >>> class MyAgent(Agent):
        ...     def on_state_change(self, old_state: int, new_state: int) -> None:
        ...         print(f"State changed: {AgentState.name(old_state)} -> {AgentState.name(new_state)}")
        ...
        >>> agent = MyAgent("agent-1", "Worker")
        >>> agent.state == AgentState.INITIALIZING
        True
        >>> agent.start()
        >>> agent.state == AgentState.RUNNABLE
        True
    """

    # Valid state transitions as defined in spec section 8
    # Maps current state -> set of valid target states
    _VALID_TRANSITIONS: dict[int, set[int]] = {
        AgentState.INITIALIZING: {AgentState.RUNNABLE},
        AgentState.RUNNABLE: {AgentState.SCHEDULED},
        AgentState.SCHEDULED: {AgentState.RUNNING},
        AgentState.RUNNING: {
            AgentState.WAITING,
            AgentState.WAITING_RESOURCES,
            AgentState.SUSPENDED,
            AgentState.COMPLETED,
            AgentState.FAILED,
            AgentState.SHUTTING_DOWN,
        },
        AgentState.WAITING: {AgentState.RUNNING},
        AgentState.WAITING_RESOURCES: {AgentState.RUNNING},
        AgentState.SUSPENDED: {AgentState.RESUMED},
        AgentState.RESUMED: {AgentState.RUNNING},
        AgentState.COMPLETED: set(),  # Terminal state
        AgentState.FAILED: {AgentState.RECOVERING},
        AgentState.RECOVERING: {AgentState.RUNNABLE, AgentState.FAILED},
        AgentState.SHUTTING_DOWN: {AgentState.FAILED},  # On timeout
    }

    def __init__(self, agent_id: str, name: str) -> None:
        """Initialize the agent.

        Args:
            agent_id: Unique identifier for this agent instance.
            name: Human-readable name for the agent.
        """
        self.agent_id = agent_id
        self.name = name
        self._preemption = PreemptionState()
        self._state: int = AgentState.INITIALIZING
        self._current_task_id: Optional[str] = None
        self._failure_reason: Optional[str] = None

    @property
    def state(self) -> int:
        """Return the current agent state (read-only).

        Returns:
            Current state as an integer constant from AgentState.
        """
        return self._state

    @property
    def state_name(self) -> str:
        """Return the human-readable name of the current state.

        Returns:
            String name of the current state.
        """
        return AgentState.name(self._state)

    def _transition_to(self, new_state: int) -> None:
        """Transition to a new state with validation.

        This method validates that the requested transition is allowed
        according to the state machine, updates the state, and calls
        the on_state_change hook.

        Args:
            new_state: The target state to transition to.

        Raises:
            StateTransitionError: If the transition is not valid.
        """
        old_state = self._state

        # Check if transition is valid
        valid_targets = self._VALID_TRANSITIONS.get(old_state, set())
        if new_state not in valid_targets:
            raise StateTransitionError(old_state, new_state)

        # Perform the transition
        self._state = new_state

        # Call the state change hook
        self.on_state_change(old_state, new_state)

    # -------------------------------------------------------------------------
    # State change lifecycle hooks (override in subclass)
    # -------------------------------------------------------------------------

    def on_state_change(self, old_state: int, new_state: int) -> None:
        """Called whenever the agent state changes.

        Override this method to react to state transitions.

        Args:
            old_state: The state before the transition.
            new_state: The state after the transition.
        """
        pass

    def on_scheduled(self, task_id: str) -> None:
        """Called when the agent is scheduled with a task.

        Override this method to prepare for task execution.

        Args:
            task_id: The identifier of the assigned task.
        """
        pass

    def on_preempt_request(self, reason: str) -> None:
        """Called when a preemption is requested.

        Override this method to handle preemption requests gracefully.
        The agent should reach a safe point and yield execution.

        Args:
            reason: The reason for the preemption request.
        """
        pass

    def on_suspend(self) -> None:
        """Called when the agent is suspended.

        Override this method to persist state or cleanup before suspension.
        """
        pass

    def on_resume(self) -> None:
        """Called when the agent resumes from suspension.

        Override this method to restore state and prepare for continued execution.
        """
        pass

    def on_recovery_start(self) -> None:
        """Called when recovery begins after a failure.

        Override this method to initiate recovery procedures.
        """
        pass

    def on_recovery_complete(self, success: bool) -> None:
        """Called when recovery completes.

        Override this method to handle recovery outcome.

        Args:
            success: True if recovery succeeded, False if it failed.
        """
        pass

    # -------------------------------------------------------------------------
    # Existing lifecycle hooks (preserved from original)
    # -------------------------------------------------------------------------

    def on_startup(self) -> None:
        """Called during agent startup initialization.

        Override to perform any startup initialization logic.
        """
        pass

    def on_shutdown(self) -> None:
        """Called during agent shutdown.

        Override to perform cleanup before the agent terminates.
        """
        pass

    # -------------------------------------------------------------------------
    # Message handling hooks (override as needed)
    # -------------------------------------------------------------------------

    def on_message(self, envelope: dict) -> None:
        """Handle an incoming data message.

        Args:
            envelope: The message envelope dictionary.
        """
        pass

    def on_control(self, envelope: dict) -> None:
        """Handle a control message.

        Control messages include preemption requests and shutdown controls.

        Args:
            envelope: The control message envelope dictionary.
        """
        # Handle preemption requests or shutdown controls
        msg = envelope
        if msg.get("content_type") == "application/json":
            try:
                import json
                body = json.loads(msg.get("payload", b""))
            except Exception:
                body = {}
            if body.get("type") == "PREEMPT_REQUEST":
                self._preemption.requested = True
                self._preemption.reason = body.get("reason")
                # Call the preemption hook
                self.on_preempt_request(self._preemption.reason or "")

    def on_tool_call(self, envelope: dict) -> None:
        """Handle a tool call request.

        Args:
            envelope: The tool call envelope dictionary.
        """
        pass

    def on_hitl(self, envelope: dict) -> None:
        """Handle a human-in-the-loop request.

        Args:
            envelope: The HITL envelope dictionary.
        """
        pass

    # -------------------------------------------------------------------------
    # Handoff protocol hooks (override as needed)
    # -------------------------------------------------------------------------

    def on_handoff_request(self, request: Any) -> None:
        """Called when another agent requests to hand off to this agent.

        Override this method to evaluate handoff requests and decide whether
        to accept or reject them. The default implementation does nothing.

        Args:
            request: HandoffRequest from the requesting agent
        """
        pass

    def on_handoff_received(self, context: Any) -> None:
        """Called when this agent receives a handoff context.

        Override this method to restore state from the handoff context
        and prepare to continue execution.

        Args:
            context: HandoffContext with conversation history, tool state, etc.
        """
        pass

    # -------------------------------------------------------------------------
    # Public state transition methods
    # -------------------------------------------------------------------------

    def start(self) -> None:
        """Transition from INITIALIZING to RUNNABLE.

        Call this after the agent has completed initialization and is
        ready to be scheduled for work.

        Raises:
            StateTransitionError: If not in INITIALIZING state.
        """
        self.on_startup()
        self._transition_to(AgentState.RUNNABLE)

    def schedule(self, task_id: str) -> None:
        """Transition from RUNNABLE to SCHEDULED.

        Called when the scheduler assigns a task to this agent.

        Args:
            task_id: The identifier of the task being assigned.

        Raises:
            StateTransitionError: If not in RUNNABLE state.
        """
        self._current_task_id = task_id
        self._transition_to(AgentState.SCHEDULED)
        self.on_scheduled(task_id)

    def run(self) -> None:
        """Transition to RUNNING state.

        Valid from SCHEDULED, WAITING, WAITING_RESOURCES, or RESUMED states.

        Raises:
            StateTransitionError: If transition is not valid from current state.
        """
        self._transition_to(AgentState.RUNNING)

    def wait(self) -> None:
        """Transition from RUNNING to WAITING.

        Call this when the agent needs to wait for external input
        (e.g., waiting for a response from another agent or service).

        Raises:
            StateTransitionError: If not in RUNNING state.
        """
        self._transition_to(AgentState.WAITING)

    def wait_resources(self) -> None:
        """Transition from RUNNING to WAITING_RESOURCES.

        Call this when the agent needs to wait for resources to become
        available (e.g., memory, compute capacity, external service limits).

        Raises:
            StateTransitionError: If not in RUNNING state.
        """
        self._transition_to(AgentState.WAITING_RESOURCES)

    def suspend(self) -> None:
        """Transition from RUNNING to SUSPENDED.

        Call this when the agent is being preempted and needs to
        suspend execution. The agent should save its state before
        calling this method.

        Raises:
            StateTransitionError: If not in RUNNING state.
        """
        self.on_suspend()
        self._transition_to(AgentState.SUSPENDED)

    def resume(self) -> None:
        """Transition from SUSPENDED to RESUMED.

        Call this when resuming a suspended agent. After resuming,
        call run() to continue execution.

        Raises:
            StateTransitionError: If not in SUSPENDED state.
        """
        self._transition_to(AgentState.RESUMED)
        self.on_resume()

    def complete(self) -> None:
        """Transition from RUNNING to COMPLETED.

        Call this when the agent has successfully finished its task.
        COMPLETED is a terminal state.

        Raises:
            StateTransitionError: If not in RUNNING state.
        """
        self._transition_to(AgentState.COMPLETED)
        self._current_task_id = None

    def fail(self, reason: str) -> None:
        """Transition to FAILED state.

        This transition is allowed from any non-terminal state where
        failure makes sense. The transition matrix restricts which
        states can transition to FAILED.

        Args:
            reason: Description of why the agent failed.

        Raises:
            StateTransitionError: If transition to FAILED is not valid
                from the current state.
        """
        self._failure_reason = reason
        # Special handling: fail can be called from RUNNING, SHUTTING_DOWN,
        # or RECOVERING (on recovery failure)
        # We need to check if FAILED is a valid target from current state
        valid_targets = self._VALID_TRANSITIONS.get(self._state, set())
        if AgentState.FAILED not in valid_targets:
            raise StateTransitionError(
                self._state,
                AgentState.FAILED,
                f"Cannot fail from {self.state_name}: {reason}"
            )
        self._transition_to(AgentState.FAILED)

    def shutdown(self) -> None:
        """Transition from RUNNING to SHUTTING_DOWN.

        Call this to initiate a graceful shutdown. The agent should
        complete any critical operations and then transition to
        either COMPLETED or FAILED.

        Raises:
            StateTransitionError: If not in RUNNING state.
        """
        self.on_shutdown()
        self._transition_to(AgentState.SHUTTING_DOWN)

    def recover(self) -> None:
        """Transition from FAILED to RECOVERING.

        Call this to initiate recovery after a failure. Override
        on_recovery_start to implement recovery logic, then call
        either complete_recovery() or fail_recovery().

        Raises:
            StateTransitionError: If not in FAILED state.
        """
        self._transition_to(AgentState.RECOVERING)
        self.on_recovery_start()

    def complete_recovery(self) -> None:
        """Complete recovery successfully, transitioning to RUNNABLE.

        Call this after recovery procedures have completed successfully.
        The agent will return to RUNNABLE state and can be scheduled again.

        Raises:
            StateTransitionError: If not in RECOVERING state.
        """
        self._failure_reason = None
        self._transition_to(AgentState.RUNNABLE)
        self.on_recovery_complete(success=True)

    def fail_recovery(self, reason: str) -> None:
        """Recovery failed, transitioning back to FAILED.

        Call this if recovery procedures fail. The agent will return
        to FAILED state.

        Args:
            reason: Description of why recovery failed.

        Raises:
            StateTransitionError: If not in RECOVERING state.
        """
        self._failure_reason = reason
        self._transition_to(AgentState.FAILED)
        self.on_recovery_complete(success=False)

    # -------------------------------------------------------------------------
    # Cooperative preemption helpers (preserved from original)
    # -------------------------------------------------------------------------

    def safe_point(self) -> bool:
        """Return True if preemption is requested and caller should yield.

        Call this at safe points in your agent's execution loop to
        check if preemption has been requested.

        Returns:
            True if preemption is requested, False otherwise.
        """
        return self._preemption.requested

    @contextlib.contextmanager
    def non_preemptible(self, *, deadline_ms: Optional[int] = None) -> ContextManager[None]:
        """Context manager for critical sections that should not be preempted.

        While inside this context, safe_point() will return False even if
        preemption has been requested. Note that the scheduler may still
        enforce a hard kill externally after the deadline.

        Args:
            deadline_ms: Optional deadline in milliseconds for the critical
                section. The scheduler may force preemption after this time.

        Yields:
            None

        Example:
            >>> with agent.non_preemptible(deadline_ms=5000):
            ...     # Critical operation that must complete
            ...     perform_critical_operation()
        """
        prev = self._preemption.requested
        try:
            # Mask preemption inside critical section (cooperative model)
            self._preemption.requested = False
            yield
        finally:
            # Restore request flag; scheduler may still enforce hard kill externally
            self._preemption.requested = prev

    # -------------------------------------------------------------------------
    # Utility methods
    # -------------------------------------------------------------------------

    @property
    def current_task_id(self) -> Optional[str]:
        """Return the current task ID if scheduled, None otherwise."""
        return self._current_task_id

    @property
    def failure_reason(self) -> Optional[str]:
        """Return the failure reason if in FAILED state, None otherwise."""
        return self._failure_reason

    def is_terminal(self) -> bool:
        """Check if the agent is in a terminal state.

        Returns:
            True if in COMPLETED or FAILED state with no valid transitions.
        """
        return self._state == AgentState.COMPLETED

    def can_transition_to(self, target_state: int) -> bool:
        """Check if a transition to the target state is valid.

        Args:
            target_state: The state to check.

        Returns:
            True if the transition is valid, False otherwise.
        """
        valid_targets = self._VALID_TRANSITIONS.get(self._state, set())
        return target_state in valid_targets

    def __repr__(self) -> str:
        """Return a string representation of the agent."""
        return (
            f"Agent(id={self.agent_id!r}, name={self.name!r}, "
            f"state={self.state_name})"
        )

    # -------------------------------------------------------------------------
    # Handoff protocol methods
    # -------------------------------------------------------------------------

    def initiate_handoff(self, to_agent: str, reason: str) -> Any:
        """Initiate a handoff to another agent.

        This method creates a handoff request with the current agent's context
        and sends it to the target agent. The context includes conversation
        history, tool state, and metadata.

        Args:
            to_agent: ID of the agent to hand off to
            reason: Human-readable explanation of why the handoff is needed

        Returns:
            HandoffResponse from the handoff client

        Example:
            >>> response = agent.initiate_handoff(
            ...     to_agent="specialist-agent-123",
            ...     reason="Task requires specialized knowledge"
            ... )
            >>> if response.accepted:
            ...     print(f"Handoff accepted: {response.handoff_id}")
        """
        from sw4rm.handoff import HandoffRequest, HandoffClient
        from sw4rm.handoff.context import serialize_context

        # Get current context
        context = self.get_handoff_context()

        # Create handoff request
        request = HandoffRequest(
            from_agent=self.agent_id,
            to_agent=to_agent,
            reason=reason,
            context_snapshot=serialize_context(context),
            preserve_history=True,
            capabilities_required=[],
            metadata={
                "current_state": self.state_name,
                "current_task_id": self._current_task_id,
            }
        )

        # Send handoff request (in production, this would use a shared client)
        client = HandoffClient()
        response = client.request_handoff(request)

        return response

    def get_handoff_context(self) -> Any:
        """Get the current context for a handoff.

        This method captures the agent's current state including conversation
        history, tool state, and metadata. Override this method to customize
        what context is included in handoffs.

        Returns:
            HandoffContext with the agent's current state

        Example:
            >>> context = agent.get_handoff_context()
            >>> print(f"History entries: {len(context.conversation_history)}")
        """
        from sw4rm.handoff import HandoffContext

        # Base implementation returns empty context
        # Subclasses should override to provide actual context
        return HandoffContext(
            conversation_history=[],
            tool_state={},
            metadata={
                "agent_id": self.agent_id,
                "agent_name": self.name,
                "state": self.state_name,
                "task_id": self._current_task_id,
            }
        )
