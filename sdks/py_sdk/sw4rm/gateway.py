"""Gateway agent helpers for SW4-004 inter-swarm delegation."""

from __future__ import annotations

import time
from dataclasses import dataclass
from typing import Callable, Iterable, Optional

from sw4rm.cancellation import (
    MIN_GRACE_PERIOD_MS,
    CancellationFlag,
    CancellationManager,
)
from sw4rm.protos import common_pb2, handoff_pb2, registry_pb2

__all__ = [
    "GatewayAgent",
    "PeerSelector",
    "CancellationFlag",
    "MIN_GRACE_PERIOD_MS",
]


NON_SERVING_AGENT_STATES = frozenset(
    {
        common_pb2.INITIALIZING,
        common_pb2.FAILED_STATE,
        common_pb2.SHUTTING_DOWN,
    }
)


@dataclass
class PeerRuntimeState:
    """Runtime health state tracked for redirect selection."""

    state: int = common_pb2.RUNNING
    last_heartbeat_ms: int = 0
    cooldown_until_ms: int = 0


class PeerSelector:
    """Health-aware selector for spillover redirect peers."""

    def __init__(
        self,
        *,
        local_agent_id: str,
        local_capabilities: Iterable[str],
        time_ms_fn: Callable[[], int],
        peer_health_fn: Callable[[registry_pb2.AgentDescriptor], bool],
        liveness_threshold_ms: int = 30_000,
    ) -> None:
        if liveness_threshold_ms < 0:
            raise ValueError("liveness_threshold_ms must be >= 0")

        self._local_agent_id = local_agent_id
        self._local_capabilities = set(local_capabilities)
        self._time_ms = time_ms_fn
        self._peer_health_fn = peer_health_fn
        self._liveness_threshold_ms = liveness_threshold_ms

        self._peers: list[registry_pb2.AgentDescriptor] = []
        self._runtime: dict[str, PeerRuntimeState] = {}
        self._rr_cursor = 0

    def set_peers(self, peers: Iterable[registry_pb2.AgentDescriptor]) -> None:
        self._peers = list(peers)
        active_ids = {peer.agent_id for peer in self._peers}
        self._runtime = {
            agent_id: runtime
            for agent_id, runtime in self._runtime.items()
            if agent_id in active_ids
        }
        now_ms = self._time_ms()
        for peer in self._peers:
            self._runtime.setdefault(
                peer.agent_id,
                PeerRuntimeState(last_heartbeat_ms=now_ms),
            )

    def update_peer_runtime_state(
        self,
        agent_id: str,
        *,
        state: Optional[int] = None,
        last_heartbeat_ms: Optional[int] = None,
        cooldown_until_ms: Optional[int] = None,
    ) -> None:
        runtime = self._runtime.setdefault(
            agent_id,
            PeerRuntimeState(last_heartbeat_ms=self._time_ms()),
        )
        if state is not None:
            runtime.state = state
        if last_heartbeat_ms is not None:
            runtime.last_heartbeat_ms = max(int(last_heartbeat_ms), 0)
        if cooldown_until_ms is not None:
            runtime.cooldown_until_ms = max(int(cooldown_until_ms), 0)

    def touch_peer_heartbeat(
        self,
        agent_id: str,
        *,
        state: Optional[int] = None,
        now_ms: Optional[int] = None,
    ) -> None:
        self.update_peer_runtime_state(
            agent_id,
            state=state,
            last_heartbeat_ms=self._time_ms() if now_ms is None else now_ms,
        )

    def record_peer_overloaded(
        self,
        agent_id: str,
        *,
        retry_after_ms: int = 0,
        local_cooldown_ms: int = 0,
    ) -> None:
        now_ms = self._time_ms()
        cooldown_ms = max(int(retry_after_ms), int(local_cooldown_ms), 0)
        runtime = self._runtime.setdefault(
            agent_id,
            PeerRuntimeState(last_heartbeat_ms=now_ms),
        )
        runtime.cooldown_until_ms = max(runtime.cooldown_until_ms, now_ms + cooldown_ms)

    def is_eligible(self, peer: registry_pb2.AgentDescriptor) -> bool:
        if peer.registration_type != registry_pb2.SWARM_GATEWAY:
            return False
        if peer.agent_id == self._local_agent_id:
            return False
        return set(peer.capabilities) == self._local_capabilities

    def select_peer(self) -> str:
        healthy = [peer for peer in self._peers if self._is_healthy(peer)]
        if not healthy:
            return ""

        idx = self._rr_cursor % len(healthy)
        self._rr_cursor += 1
        return healthy[idx].agent_id

    def _is_healthy(self, peer: registry_pb2.AgentDescriptor) -> bool:
        if not self.is_eligible(peer):
            return False
        if not self._peer_health_fn(peer):
            return False

        runtime = self._runtime.get(peer.agent_id)
        if runtime is None:
            return False
        now_ms = self._time_ms()
        if runtime.cooldown_until_ms > now_ms:
            return False
        if now_ms - runtime.last_heartbeat_ms > self._liveness_threshold_ms:
            return False
        if runtime.state in NON_SERVING_AGENT_STATES:
            return False
        return True


class GatewayAgent:
    """Base helper implementing SW4-004 gateway-side guardrails.

    This class focuses on protocol-level checks and helpers:
    - SWARM_GATEWAY registration metadata
    - max concurrent delegation enforcement (OVERLOADED)
    - depth validation using local lineage knowledge
    - monotonic budget propagation to child delegations
    - cancellation flag tracking and grace expiry checks
    """

    def __init__(
        self,
        *,
        agent_id: str,
        name: Optional[str] = None,
        description: str = "",
        capabilities: Optional[Iterable[str]] = None,
        internal_agents: Optional[Iterable[str]] = None,
        max_concurrent_delegations: int = 2,
        max_delegation_depth: int = 3,
        retry_after_ms: int = 1000,
        peer_descriptors: Optional[Iterable[registry_pb2.AgentDescriptor]] = None,
        peer_health_fn: Optional[Callable[[registry_pb2.AgentDescriptor], bool]] = None,
        time_ms_fn: Optional[Callable[[], int]] = None,
        peer_liveness_threshold_ms: int = 30_000,
    ) -> None:
        if max_concurrent_delegations < 0:
            raise ValueError("max_concurrent_delegations must be >= 0")
        if max_delegation_depth <= 0:
            raise ValueError("max_delegation_depth must be > 0")
        if retry_after_ms < 0:
            raise ValueError("retry_after_ms must be >= 0")

        self.agent_id = agent_id
        self.name = name or agent_id
        self.description = description
        self.capabilities = list(capabilities or [])
        self.internal_agents = set(internal_agents or [])
        self.max_concurrent_delegations = max_concurrent_delegations
        self.max_delegation_depth = max_delegation_depth
        self.retry_after_ms = retry_after_ms
        self._peer_descriptors = list(peer_descriptors or [])
        self._peer_health_fn = peer_health_fn or (lambda _peer: True)
        self._time_ms = time_ms_fn or (lambda: int(time.time() * 1000))
        self._peer_selector = PeerSelector(
            local_agent_id=self.agent_id,
            local_capabilities=self.capabilities,
            time_ms_fn=self._time_ms,
            peer_health_fn=self._peer_health_fn,
            liveness_threshold_ms=peer_liveness_threshold_ms,
        )
        self._peer_selector.set_peers(self._peer_descriptors)
        self.cancellation_manager = CancellationManager(time_ms_fn=self._time_ms)

        self.depth_registry: dict[str, int] = {}
        self.child_delegations: dict[str, list[str]] = (
            self.cancellation_manager.child_delegations
        )
        self.cancellation_flags: dict[str, CancellationFlag] = (
            self.cancellation_manager.cancellation_flags
        )
        self._active_delegations: set[str] = set()

    @property
    def active_delegation_count(self) -> int:
        """Current number of active delegations."""
        return len(self._active_delegations)

    def to_agent_descriptor(self) -> registry_pb2.AgentDescriptor:
        """Build an AgentDescriptor for registry registration."""
        return registry_pb2.AgentDescriptor(
            agent_id=self.agent_id,
            name=self.name,
            description=self.description,
            capabilities=self.capabilities,
            communication_class=common_pb2.STANDARD,
            registration_type=registry_pb2.SWARM_GATEWAY,
            max_concurrent_delegations=self.max_concurrent_delegations,
        )

    def register_verified_depth(self, correlation_id: str, depth: int) -> None:
        """Persist independently verified depth for a correlation id."""
        if depth < 0:
            raise ValueError("depth must be >= 0")
        self.depth_registry[correlation_id] = depth

    def register_child_delegation(
        self, parent_correlation_id: str, child_correlation_id: str
    ) -> None:
        """Link parent/child delegation ids for cancellation cascade."""
        self.cancellation_manager.register_child_delegation(
            parent_correlation_id, child_correlation_id
        )

    def set_peer_descriptors(
        self, peers: Iterable[registry_pb2.AgentDescriptor]
    ) -> None:
        """Replace peer descriptors used for spillover redirect decisions."""
        self._peer_descriptors = list(peers)
        self._peer_selector.set_peers(self._peer_descriptors)

    def update_peer_runtime_state(
        self,
        agent_id: str,
        *,
        state: Optional[int] = None,
        last_heartbeat_ms: Optional[int] = None,
        cooldown_until_ms: Optional[int] = None,
    ) -> None:
        """Update tracked runtime state for a peer gateway."""
        self._peer_selector.update_peer_runtime_state(
            agent_id,
            state=state,
            last_heartbeat_ms=last_heartbeat_ms,
            cooldown_until_ms=cooldown_until_ms,
        )

    def touch_peer_heartbeat(
        self,
        agent_id: str,
        *,
        state: Optional[int] = None,
        now_ms: Optional[int] = None,
    ) -> None:
        """Record a new heartbeat for a peer gateway."""
        self._peer_selector.touch_peer_heartbeat(agent_id, state=state, now_ms=now_ms)

    def record_peer_overloaded(
        self,
        agent_id: str,
        *,
        retry_after_ms: int = 0,
        local_cooldown_ms: int = 0,
    ) -> None:
        """Apply temporary cooldown to a recently overloaded peer."""
        self._peer_selector.record_peer_overloaded(
            agent_id,
            retry_after_ms=retry_after_ms,
            local_cooldown_ms=local_cooldown_ms,
        )

    def _is_eligible_redirect_peer(self, peer: registry_pb2.AgentDescriptor) -> bool:
        return self._peer_selector.is_eligible(peer)

    def _select_redirect_peer(self) -> str:
        return self._peer_selector.select_peer()

    def _overloaded_response(self, request_id: str) -> handoff_pb2.HandoffResponse:
        return handoff_pb2.HandoffResponse(
            request_id=request_id,
            accepted=False,
            rejection_reason="Gateway at capacity",
            rejection_code=common_pb2.OVERLOADED,
            retry_after_ms=self.retry_after_ms,
        )

    def _cancelled_response(self, request_id: str) -> handoff_pb2.HandoffResponse:
        return handoff_pb2.HandoffResponse(
            request_id=request_id,
            accepted=False,
            rejection_reason="Delegation has already been cancelled",
            rejection_code=common_pb2.FORCED_PREEMPTION,
        )

    def _verify_depth(
        self, request: handoff_pb2.HandoffRequest, parent_correlation_id: Optional[str]
    ) -> int:
        if parent_correlation_id and parent_correlation_id in self.depth_registry:
            return self.depth_registry[parent_correlation_id] + 1
        if request.request_id in self.depth_registry:
            return self.depth_registry[request.request_id]
        if request.budget.ByteSize() == 0:
            return 0
        return request.budget.current_depth

    def _max_depth_limit(self, request: handoff_pb2.HandoffRequest) -> int:
        if request.budget.ByteSize() == 0 or request.budget.max_delegation_depth == 0:
            return self.max_delegation_depth
        return min(self.max_delegation_depth, request.budget.max_delegation_depth)

    def handle_handoff_request(
        self,
        request: handoff_pb2.HandoffRequest,
        *,
        parent_correlation_id: Optional[str] = None,
    ) -> handoff_pb2.HandoffResponse:
        """Validate and accept/reject a cross-swarm handoff request."""
        if request.to_agent in self.internal_agents:
            return handoff_pb2.HandoffResponse(
                request_id=request.request_id,
                accepted=False,
                rejection_reason="Internal agent not externally addressable",
                rejection_code=common_pb2.PERMISSION_DENIED,
            )

        if request.budget.ByteSize() == 0:
            return handoff_pb2.HandoffResponse(
                request_id=request.request_id,
                accepted=False,
                rejection_reason="BudgetEnvelope is required for cross-swarm delegation",
                rejection_code=common_pb2.VALIDATION_ERROR,
            )
        if request.budget.deadline_epoch_ms == 0:
            return handoff_pb2.HandoffResponse(
                request_id=request.request_id,
                accepted=False,
                rejection_reason="deadline_epoch_ms is required",
                rejection_code=common_pb2.VALIDATION_ERROR,
            )

        if self.is_cancelled(request.request_id):
            return self._cancelled_response(request.request_id)

        verified_depth = self._verify_depth(request, parent_correlation_id)
        if verified_depth >= self._max_depth_limit(request):
            return handoff_pb2.HandoffResponse(
                request_id=request.request_id,
                accepted=False,
                rejection_reason=(
                    f"Delegation depth {verified_depth} exceeds max "
                    f"{self._max_depth_limit(request)}"
                ),
                rejection_code=common_pb2.VALIDATION_ERROR,
            )

        if self._time_ms() > request.budget.deadline_epoch_ms:
            return handoff_pb2.HandoffResponse(
                request_id=request.request_id,
                accepted=False,
                rejection_reason="Deadline already expired",
                rejection_code=common_pb2.ACK_TIMEOUT,
            )

        if self.active_delegation_count >= self.max_concurrent_delegations:
            if request.delegation_policy.allow_spillover_routing:
                redirect_to = self._select_redirect_peer()
                if redirect_to:
                    return handoff_pb2.HandoffResponse(
                        request_id=request.request_id,
                        accepted=False,
                        rejection_reason="Gateway at capacity; redirect to peer gateway",
                        rejection_code=common_pb2.REDIRECT,
                        redirect_to_agent_id=redirect_to,
                    )
            return self._overloaded_response(request.request_id)

        if self.is_cancelled(request.request_id):
            return self._cancelled_response(request.request_id)

        self._active_delegations.add(request.request_id)
        self.depth_registry[request.request_id] = verified_depth
        return handoff_pb2.HandoffResponse(
            request_id=request.request_id,
            accepted=True,
            accepting_agent=self.agent_id,
        )

    def complete_delegation(self, correlation_id: str) -> None:
        """Mark a delegation as no longer active."""
        self._active_delegations.discard(correlation_id)

    def propagate_budget(
        self,
        parent_budget: handoff_pb2.BudgetEnvelope,
        *,
        token_spent: int = 0,
        wall_time_spent_ms: int = 0,
    ) -> handoff_pb2.BudgetEnvelope:
        """Create a monotonic child budget from a parent budget."""
        if token_spent < 0:
            raise ValueError("token_spent must be >= 0")
        if wall_time_spent_ms < 0:
            raise ValueError("wall_time_spent_ms must be >= 0")

        max_depth = (
            parent_budget.max_delegation_depth
            if parent_budget.max_delegation_depth > 0
            else self.max_delegation_depth
        )

        return handoff_pb2.BudgetEnvelope(
            token_budget_remaining=max(parent_budget.token_budget_remaining - token_spent, 0),
            wall_time_remaining_ms=max(parent_budget.wall_time_remaining_ms - wall_time_spent_ms, 0),
            deadline_epoch_ms=parent_budget.deadline_epoch_ms,
            current_depth=parent_budget.current_depth + 1,
            max_delegation_depth=max_depth,
        )

    def handle_cancel_delegation(
        self, cancel: handoff_pb2.CancelDelegation
    ) -> handoff_pb2.CancelDelegationResponse:
        """Set cancellation flags and cascade to child correlations."""
        return self.cancellation_manager.handle_cancel_delegation(cancel)

    def is_cancelled(self, correlation_id: str) -> bool:
        """Return True when a cancellation flag exists and is active."""
        return self.cancellation_manager.is_cancelled(correlation_id)

    def is_grace_expired(
        self, correlation_id: str, *, now_ms: Optional[int] = None
    ) -> bool:
        """Return True when cancellation grace period has elapsed."""
        return self.cancellation_manager.is_grace_expired(correlation_id, now_ms=now_ms)

    def force_preempt_expired_delegations(
        self, *, now_ms: Optional[int] = None
    ) -> set[str]:
        """Force-preempt active delegations whose cancellation grace has expired."""
        forced = self.cancellation_manager.collect_forced_preemptions(
            self._active_delegations, now_ms=now_ms
        )
        self._active_delegations.difference_update(forced)
        return forced
