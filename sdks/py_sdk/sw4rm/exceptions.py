"""Custom exception hierarchy for SW4RM SDK.

This module defines a comprehensive exception hierarchy for all SW4RM errors,
providing structured error information with serialization support and mapping
to protocol error codes from constants.py.

All exceptions inherit from SW4RMError and include:
- Human-readable error messages
- Optional error codes from protocol constants
- Serialization via to_dict() for logging and debugging
- Rich contextual information specific to each error type
"""

from __future__ import annotations

from typing import Any, Optional
from . import constants as C


class SW4RMError(Exception):
    """Base exception for all SW4RM errors.

    This is the root of the exception hierarchy. All SW4RM-specific exceptions
    should inherit from this class to enable catch-all error handling.

    Attributes:
        message: Human-readable error description
        error_code: Optional protocol error code from constants.py
    """

    def __init__(
        self,
        message: str,
        error_code: Optional[int] = None
    ) -> None:
        """Initialize the base SW4RM error.

        Args:
            message: Human-readable error description
            error_code: Optional error code from constants.py ErrorCode values
        """
        super().__init__(message)
        self.message = message
        self.error_code = error_code if error_code is not None else C.INTERNAL_ERROR

    def __str__(self) -> str:
        """Return human-readable error message."""
        return f"{self.__class__.__name__}: {self.message} (code={self.error_code})"

    def to_dict(self) -> dict[str, Any]:
        """Serialize exception to dictionary for logging and debugging.

        Returns:
            Dictionary containing exception type, message, and error code
        """
        return {
            "type": self.__class__.__name__,
            "message": self.message,
            "error_code": self.error_code,
        }


class RPCError(SW4RMError):
    """Exception for gRPC communication failures.

    Raised when gRPC calls fail due to network issues, service unavailability,
    or protocol errors.

    Attributes:
        message: Human-readable error description
        error_code: Protocol error code (defaults to NO_ROUTE)
        status_code: gRPC status code (e.g., "UNAVAILABLE", "DEADLINE_EXCEEDED")
        details: Detailed error information from gRPC
    """

    def __init__(
        self,
        message: str,
        status_code: str,
        details: str,
        error_code: Optional[int] = None
    ) -> None:
        """Initialize RPC error.

        Args:
            message: Human-readable error description
            status_code: gRPC status code string
            details: Detailed error information from gRPC
            error_code: Optional protocol error code (defaults to NO_ROUTE)
        """
        super().__init__(message, error_code or C.NO_ROUTE)
        self.status_code = status_code
        self.details = details

    def __str__(self) -> str:
        """Return human-readable error message with RPC details."""
        return (
            f"{self.__class__.__name__}: {self.message} "
            f"(status={self.status_code}, code={self.error_code}): {self.details}"
        )

    def to_dict(self) -> dict[str, Any]:
        """Serialize exception to dictionary.

        Returns:
            Dictionary with type, message, error_code, status_code, and details
        """
        base = super().to_dict()
        base.update({
            "status_code": self.status_code,
            "details": self.details,
        })
        return base


class ValidationError(SW4RMError):
    """Exception for input validation failures.

    Raised when user input or API parameters fail validation constraints
    such as type checks, range checks, or format requirements.

    Attributes:
        message: Human-readable error description
        error_code: Protocol error code (VALIDATION_ERROR)
        field: Name of the field that failed validation
        constraint: Description of the violated constraint
    """

    def __init__(
        self,
        message: str,
        field: str,
        constraint: str,
        error_code: Optional[int] = None
    ) -> None:
        """Initialize validation error.

        Args:
            message: Human-readable error description
            field: Name of the field that failed validation
            constraint: Description of the violated constraint
            error_code: Optional protocol error code (defaults to VALIDATION_ERROR)
        """
        super().__init__(message, error_code or C.VALIDATION_ERROR)
        self.field = field
        self.constraint = constraint

    def __str__(self) -> str:
        """Return human-readable error message with field and constraint."""
        return (
            f"{self.__class__.__name__}: {self.message} "
            f"(field='{self.field}', constraint='{self.constraint}', code={self.error_code})"
        )

    def to_dict(self) -> dict[str, Any]:
        """Serialize exception to dictionary.

        Returns:
            Dictionary with type, message, error_code, field, and constraint
        """
        base = super().to_dict()
        base.update({
            "field": self.field,
            "constraint": self.constraint,
        })
        return base


class StateTransitionError(SW4RMError):
    """Exception for invalid agent state transitions.

    Raised when attempting to transition an agent to a state that is not
    allowed from its current state according to the state machine rules.

    Attributes:
        message: Human-readable error description
        error_code: Protocol error code (defaults to INTERNAL_ERROR)
        current_state: The agent's current state
        requested_state: The state that was requested
        allowed_transitions: List of valid transitions from current state
    """

    def __init__(
        self,
        message: str,
        current_state: str,
        requested_state: str,
        allowed_transitions: list[str],
        error_code: Optional[int] = None
    ) -> None:
        """Initialize state transition error.

        Args:
            message: Human-readable error description
            current_state: The agent's current state
            requested_state: The state that was requested
            allowed_transitions: List of valid state transitions
            error_code: Optional protocol error code (defaults to INTERNAL_ERROR)
        """
        super().__init__(message, error_code or C.INTERNAL_ERROR)
        self.current_state = current_state
        self.requested_state = requested_state
        self.allowed_transitions = allowed_transitions

    def __str__(self) -> str:
        """Return human-readable error message with state transition details."""
        allowed = ", ".join(self.allowed_transitions) if self.allowed_transitions else "none"
        return (
            f"{self.__class__.__name__}: {self.message} "
            f"(current='{self.current_state}', requested='{self.requested_state}', "
            f"allowed=[{allowed}], code={self.error_code})"
        )

    def to_dict(self) -> dict[str, Any]:
        """Serialize exception to dictionary.

        Returns:
            Dictionary with type, message, error_code, and state information
        """
        base = super().to_dict()
        base.update({
            "current_state": self.current_state,
            "requested_state": self.requested_state,
            "allowed_transitions": self.allowed_transitions,
        })
        return base


class PolicyViolationError(SW4RMError):
    """Exception for policy enforcement failures.

    Raised when an operation violates a configured policy such as resource
    limits, access controls, or behavioral constraints.

    Attributes:
        message: Human-readable error description
        error_code: Protocol error code (PERMISSION_DENIED)
        policy_id: Identifier of the violated policy
        violation: Description of what was violated
    """

    def __init__(
        self,
        message: str,
        policy_id: str,
        violation: str,
        error_code: Optional[int] = None
    ) -> None:
        """Initialize policy violation error.

        Args:
            message: Human-readable error description
            policy_id: Identifier of the violated policy
            violation: Description of what was violated
            error_code: Optional protocol error code (defaults to PERMISSION_DENIED)
        """
        super().__init__(message, error_code or C.PERMISSION_DENIED)
        self.policy_id = policy_id
        self.violation = violation

    def __str__(self) -> str:
        """Return human-readable error message with policy details."""
        return (
            f"{self.__class__.__name__}: {self.message} "
            f"(policy='{self.policy_id}', violation='{self.violation}', code={self.error_code})"
        )

    def to_dict(self) -> dict[str, Any]:
        """Serialize exception to dictionary.

        Returns:
            Dictionary with type, message, error_code, policy_id, and violation
        """
        base = super().to_dict()
        base.update({
            "policy_id": self.policy_id,
            "violation": self.violation,
        })
        return base


class TimeoutError(SW4RMError):
    """Exception for operation timeouts.

    Raised when an operation exceeds its configured timeout duration.
    Note: This shadows the built-in TimeoutError to provide SW4RM-specific
    context and error code mapping.

    Attributes:
        message: Human-readable error description
        error_code: Protocol error code (ACK_TIMEOUT or TOOL_TIMEOUT)
        operation: Name or description of the timed-out operation
        timeout_ms: Timeout duration in milliseconds
    """

    def __init__(
        self,
        message: str,
        operation: str,
        timeout_ms: int,
        error_code: Optional[int] = None
    ) -> None:
        """Initialize timeout error.

        Args:
            message: Human-readable error description
            operation: Name or description of the timed-out operation
            timeout_ms: Timeout duration in milliseconds
            error_code: Optional protocol error code (defaults to ACK_TIMEOUT)
        """
        super().__init__(message, error_code or C.ACK_TIMEOUT)
        self.operation = operation
        self.timeout_ms = timeout_ms

    def __str__(self) -> str:
        """Return human-readable error message with timeout details."""
        return (
            f"{self.__class__.__name__}: {self.message} "
            f"(operation='{self.operation}', timeout={self.timeout_ms}ms, code={self.error_code})"
        )

    def to_dict(self) -> dict[str, Any]:
        """Serialize exception to dictionary.

        Returns:
            Dictionary with type, message, error_code, operation, and timeout_ms
        """
        base = super().to_dict()
        base.update({
            "operation": self.operation,
            "timeout_ms": self.timeout_ms,
        })
        return base


class PreemptionError(SW4RMError):
    """Exception for preemption-related failures.

    Raised when an agent is preempted (interrupted) either gracefully or
    forcefully, or when preemption-related operations fail.

    Attributes:
        message: Human-readable error description
        error_code: Protocol error code (FORCED_PREEMPTION if forced)
        reason: Explanation of why preemption occurred
        was_forced: Whether this was a forced (non-graceful) preemption
    """

    def __init__(
        self,
        message: str,
        reason: str,
        was_forced: bool,
        error_code: Optional[int] = None
    ) -> None:
        """Initialize preemption error.

        Args:
            message: Human-readable error description
            reason: Explanation of why preemption occurred
            was_forced: Whether this was a forced preemption
            error_code: Optional protocol error code (defaults based on was_forced)
        """
        if error_code is None:
            error_code = C.FORCED_PREEMPTION if was_forced else C.INTERNAL_ERROR
        super().__init__(message, error_code)
        self.reason = reason
        self.was_forced = was_forced

    def __str__(self) -> str:
        """Return human-readable error message with preemption details."""
        preemption_type = "forced" if self.was_forced else "graceful"
        return (
            f"{self.__class__.__name__}: {self.message} "
            f"(type={preemption_type}, reason='{self.reason}', code={self.error_code})"
        )

    def to_dict(self) -> dict[str, Any]:
        """Serialize exception to dictionary.

        Returns:
            Dictionary with type, message, error_code, reason, and was_forced
        """
        base = super().to_dict()
        base.update({
            "reason": self.reason,
            "was_forced": self.was_forced,
        })
        return base


class WorktreeError(SW4RMError):
    """Exception for worktree binding and management failures.

    Raised when worktree operations fail, such as binding failures,
    state inconsistencies, or resource conflicts.

    Attributes:
        message: Human-readable error description
        error_code: Protocol error code (defaults to INTERNAL_ERROR)
        worktree_id: Identifier of the affected worktree
        state: Current state of the worktree
    """

    def __init__(
        self,
        message: str,
        worktree_id: str,
        state: str,
        error_code: Optional[int] = None
    ) -> None:
        """Initialize worktree error.

        Args:
            message: Human-readable error description
            worktree_id: Identifier of the affected worktree
            state: Current state of the worktree
            error_code: Optional protocol error code (defaults to INTERNAL_ERROR)
        """
        super().__init__(message, error_code or C.INTERNAL_ERROR)
        self.worktree_id = worktree_id
        self.state = state

    def __str__(self) -> str:
        """Return human-readable error message with worktree details."""
        return (
            f"{self.__class__.__name__}: {self.message} "
            f"(worktree_id='{self.worktree_id}', state='{self.state}', code={self.error_code})"
        )

    def to_dict(self) -> dict[str, Any]:
        """Serialize exception to dictionary.

        Returns:
            Dictionary with type, message, error_code, worktree_id, and state
        """
        base = super().to_dict()
        base.update({
            "worktree_id": self.worktree_id,
            "state": self.state,
        })
        return base


class NegotiationError(SW4RMError):
    """Exception for negotiation protocol failures.

    Raised when multi-agent negotiation operations fail, such as proposal
    rejections, consensus failures, or protocol violations.

    Attributes:
        message: Human-readable error description
        error_code: Protocol error code (defaults to INTERNAL_ERROR)
        negotiation_id: Identifier of the failed negotiation
        phase: Current phase of the negotiation (e.g., "proposal", "voting")
    """

    def __init__(
        self,
        message: str,
        negotiation_id: str,
        phase: str,
        error_code: Optional[int] = None
    ) -> None:
        """Initialize negotiation error.

        Args:
            message: Human-readable error description
            negotiation_id: Identifier of the failed negotiation
            phase: Current phase of the negotiation
            error_code: Optional protocol error code (defaults to INTERNAL_ERROR)
        """
        super().__init__(message, error_code or C.INTERNAL_ERROR)
        self.negotiation_id = negotiation_id
        self.phase = phase

    def __str__(self) -> str:
        """Return human-readable error message with negotiation details."""
        return (
            f"{self.__class__.__name__}: {self.message} "
            f"(negotiation_id='{self.negotiation_id}', phase='{self.phase}', code={self.error_code})"
        )

    def to_dict(self) -> dict[str, Any]:
        """Serialize exception to dictionary.

        Returns:
            Dictionary with type, message, error_code, negotiation_id, and phase
        """
        base = super().to_dict()
        base.update({
            "negotiation_id": self.negotiation_id,
            "phase": self.phase,
        })
        return base
