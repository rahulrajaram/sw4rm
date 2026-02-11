"""State transition validation matrix for Agent lifecycle.

Provides a transition matrix matching spec section 8 state diagram.
All SDKs (Python, JS, Rust) share the same transition rules.
"""
from __future__ import annotations

from . import constants as C
from .exceptions import StateTransitionError

# Valid transitions: maps each state to the set of valid target states.
_VALID_TRANSITIONS: dict[int, set[int]] = {
    # INITIALIZING -> RUNNABLE, FAILED (init timeout)
    C.INITIALIZING: {C.RUNNABLE, C.FAILED},
    # RUNNABLE -> SCHEDULED
    C.RUNNABLE: {C.SCHEDULED},
    # SCHEDULED -> RUNNING
    C.SCHEDULED: {C.RUNNING},
    # RUNNING -> WAITING, WAITING_RESOURCES, SUSPENDED, COMPLETED, FAILED, SHUTTING_DOWN
    C.RUNNING: {
        C.WAITING,
        C.WAITING_RESOURCES,
        C.SUSPENDED,
        C.COMPLETED,
        C.FAILED,
        C.SHUTTING_DOWN,
    },
    # WAITING -> RUNNING
    C.WAITING: {C.RUNNING},
    # WAITING_RESOURCES -> RUNNING, FAILED (resource timeout)
    C.WAITING_RESOURCES: {C.RUNNING, C.FAILED},
    # SUSPENDED -> RESUMED, FAILED (suspension timeout)
    C.SUSPENDED: {C.RESUMED, C.FAILED},
    # RESUMED -> RUNNING
    C.RESUMED: {C.RUNNING},
    # COMPLETED -> RUNNABLE
    C.COMPLETED: {C.RUNNABLE},
    # FAILED -> RECOVERING
    C.FAILED: {C.RECOVERING},
    # SHUTTING_DOWN -> FAILED (shutdown timeout)
    C.SHUTTING_DOWN: {C.FAILED},
    # RECOVERING -> RUNNABLE, SHUTTING_DOWN (abort), FAILED (recovery timeout)
    C.RECOVERING: {C.RUNNABLE, C.SHUTTING_DOWN, C.FAILED},
}

_STATE_NAMES: dict[int, str] = {
    C.AGENT_STATE_UNSPECIFIED: "UNSPECIFIED",
    C.INITIALIZING: "INITIALIZING",
    C.RUNNABLE: "RUNNABLE",
    C.SCHEDULED: "SCHEDULED",
    C.RUNNING: "RUNNING",
    C.WAITING: "WAITING",
    C.WAITING_RESOURCES: "WAITING_RESOURCES",
    C.SUSPENDED: "SUSPENDED",
    C.RESUMED: "RESUMED",
    C.COMPLETED: "COMPLETED",
    C.FAILED: "FAILED",
    C.SHUTTING_DOWN: "SHUTTING_DOWN",
    C.RECOVERING: "RECOVERING",
}


def is_valid_transition(from_state: int, to_state: int) -> bool:
    """Check if a state transition is valid per spec section 8."""
    targets = _VALID_TRANSITIONS.get(from_state)
    if targets is None:
        return False
    return to_state in targets


def valid_transitions(from_state: int) -> list[int]:
    """Get all valid target states from a given state."""
    targets = _VALID_TRANSITIONS.get(from_state)
    if targets is None:
        return []
    return sorted(targets)


def validate_transition(from_state: int, to_state: int) -> None:
    """Validate a state transition, raising StateTransitionError if invalid."""
    if not is_valid_transition(from_state, to_state):
        allowed = [state_name(s) for s in valid_transitions(from_state)]
        raise StateTransitionError(
            message=f"Invalid state transition from {state_name(from_state)} to {state_name(to_state)}",
            current_state=state_name(from_state),
            requested_state=state_name(to_state),
            allowed_transitions=allowed,
        )


def state_name(state: int) -> str:
    """Get human-readable name for a state."""
    return _STATE_NAMES.get(state, "UNKNOWN")
