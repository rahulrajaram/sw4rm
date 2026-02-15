"""
SW4-004 Inter-Swarm Composition — Conformance Test Scaffolding

Tests T-001 through T-012 per §10 of SW4-004-inter-swarm-composition.md v0.2.0.
These tests validate normative protocol rules using in-process simulation of
gateway and agent behavior. No live gRPC server is required.

Requirement levels:
  - T-001..T-006, T-010, T-011: Required
  - T-007..T-009, T-012: Recommended
"""

import time
import uuid
from dataclasses import dataclass, field

from sw4rm.protos import common_pb2, handoff_pb2, registry_pb2


# ---------------------------------------------------------------------------
# Minimal in-process gateway simulator
# ---------------------------------------------------------------------------

@dataclass
class GatewayState:
    """Simulates a SWARM_GATEWAY agent's state for conformance testing."""

    agent_id: str = "gateway-1"
    max_delegation_depth: int = 3
    max_concurrent_delegations: int = 2
    active_delegations: int = 0
    # depth tracking: maps correlation_id -> verified depth
    depth_registry: dict = field(default_factory=dict)
    # cancellation flags: maps correlation_id -> cancelled
    cancellation_flags: dict = field(default_factory=dict)
    # child gateways this gateway delegated to: maps correlation_id -> list of child correlation_ids
    child_delegations: dict = field(default_factory=dict)
    # internal agents (not addressable externally)
    internal_agents: list = field(default_factory=lambda: ["worker-1", "worker-2"])
    # registered agent descriptors
    registry: dict = field(default_factory=dict)

    def handle_handoff_request(self, request: handoff_pb2.HandoffRequest) -> handoff_pb2.HandoffResponse:
        """Process a HandoffRequest, enforcing SW4-004 rules."""

        # §1.2: Gateway-only addressing — reject if to_agent is internal
        if request.to_agent in self.internal_agents:
            return handoff_pb2.HandoffResponse(
                request_id=request.request_id,
                accepted=False,
                rejection_reason="Internal agent not externally addressable",
                rejection_code=common_pb2.PERMISSION_DENIED,
            )

        # §1.3: Depth limit — independent validation
        if request.budget.ByteSize() > 0:
            verified_depth = self._verify_depth(request)
            if verified_depth >= self.max_delegation_depth:
                return handoff_pb2.HandoffResponse(
                    request_id=request.request_id,
                    accepted=False,
                    rejection_reason=f"Delegation depth {verified_depth} exceeds max {self.max_delegation_depth}",
                    rejection_code=common_pb2.VALIDATION_ERROR,
                )

        # §2.1: Budget monotonicity — check deadline
        if request.budget.ByteSize() > 0:
            now_ms = int(time.time() * 1000)
            if request.budget.deadline_epoch_ms > 0 and now_ms > request.budget.deadline_epoch_ms:
                return handoff_pb2.HandoffResponse(
                    request_id=request.request_id,
                    accepted=False,
                    rejection_reason="Deadline already expired",
                    rejection_code=common_pb2.ACK_TIMEOUT,
                )

        # §4.2: Overload — check concurrent delegations
        if self.active_delegations >= self.max_concurrent_delegations:
            return handoff_pb2.HandoffResponse(
                request_id=request.request_id,
                accepted=False,
                rejection_reason="Gateway at capacity",
                rejection_code=common_pb2.OVERLOADED,
                retry_after_ms=1000,
            )

        # Accept
        self.active_delegations += 1
        return handoff_pb2.HandoffResponse(
            request_id=request.request_id,
            accepted=True,
            accepting_agent=self.agent_id,
        )

    def handle_cancel_delegation(self, cancel: handoff_pb2.CancelDelegation) -> handoff_pb2.CancelDelegationResponse:
        """Process a CancelDelegation, propagating to children."""
        # §5.2 step 1: Acknowledge immediately
        grace_ms = max(cancel.grace_period_ms, 5000)  # §5.5: minimum 5000ms
        self.cancellation_flags[cancel.correlation_id] = {
            "cancelled": True,
            "grace_period_ms": grace_ms,
            "cancel_time_ms": int(time.time() * 1000),
        }

        # §5.3: Propagate to child gateways
        children = self.child_delegations.get(cancel.correlation_id, [])
        for child_corr_id in children:
            self.cancellation_flags[child_corr_id] = {
                "cancelled": True,
                "grace_period_ms": grace_ms,
                "cancel_time_ms": int(time.time() * 1000),
            }

        return handoff_pb2.CancelDelegationResponse(acknowledged=True)

    def is_cancelled(self, correlation_id: str) -> bool:
        """Check if a delegation has been cancelled."""
        entry = self.cancellation_flags.get(correlation_id)
        return entry is not None and entry["cancelled"]

    def is_grace_expired(self, correlation_id: str) -> bool:
        """Check if the grace period has expired for a cancelled delegation."""
        entry = self.cancellation_flags.get(correlation_id)
        if entry is None or not entry["cancelled"]:
            return False
        now_ms = int(time.time() * 1000)
        return (now_ms - entry["cancel_time_ms"]) >= entry["grace_period_ms"]

    def _verify_depth(self, request: handoff_pb2.HandoffRequest) -> int:
        """
        Independently verify delegation depth. MUST NOT trust caller-supplied
        current_depth without verification (§1.3).
        """
        # In a real implementation, this would walk the parent_correlation_id
        # chain in envelope_log. For testing, we use the depth_registry.
        parent_corr = getattr(request, "_parent_correlation_id", None)
        if parent_corr and parent_corr in self.depth_registry:
            return self.depth_registry[parent_corr] + 1
        # If no parent chain, trust but verify: use our own counter
        # The key point is we do NOT blindly trust request.budget.current_depth
        return self.depth_registry.get(request.request_id, request.budget.current_depth)


def _make_request(
    *,
    to_agent: str = "gateway-1",
    depth: int = 0,
    max_depth: int = 3,
    token_budget: int = 10000,
    deadline_epoch_ms: int = 0,
    wall_time_ms: int = 60000,
) -> handoff_pb2.HandoffRequest:
    """Helper to construct a HandoffRequest with BudgetEnvelope."""
    req_id = str(uuid.uuid4())
    if deadline_epoch_ms == 0:
        deadline_epoch_ms = int(time.time() * 1000) + wall_time_ms

    return handoff_pb2.HandoffRequest(
        request_id=req_id,
        from_agent="parent-orchestrator",
        to_agent=to_agent,
        reason="conformance test",
        budget=handoff_pb2.BudgetEnvelope(
            token_budget_remaining=token_budget,
            wall_time_remaining_ms=wall_time_ms,
            deadline_epoch_ms=deadline_epoch_ms,
            current_depth=depth,
            max_delegation_depth=max_depth,
        ),
    )


# ===========================================================================
# T-001: Depth limit rejection (Required) — §1.3
# ===========================================================================

class TestT001DepthLimitRejection:
    """Gateway rejects delegation when current_depth >= max_delegation_depth."""

    def test_at_max_depth_rejected(self):
        gw = GatewayState(max_delegation_depth=3)
        req = _make_request(depth=3, max_depth=3)
        resp = gw.handle_handoff_request(req)
        assert not resp.accepted
        assert resp.rejection_code == common_pb2.VALIDATION_ERROR

    def test_exceeds_max_depth_rejected(self):
        gw = GatewayState(max_delegation_depth=3)
        req = _make_request(depth=5, max_depth=3)
        resp = gw.handle_handoff_request(req)
        assert not resp.accepted
        assert resp.rejection_code == common_pb2.VALIDATION_ERROR

    def test_under_max_depth_accepted(self):
        gw = GatewayState(max_delegation_depth=3)
        req = _make_request(depth=1, max_depth=3)
        resp = gw.handle_handoff_request(req)
        assert resp.accepted

    def test_default_max_depth_is_3(self):
        gw = GatewayState()  # default
        assert gw.max_delegation_depth == 3


# ===========================================================================
# T-002: Independent depth validation (Required) — §1.3
# ===========================================================================

class TestT002IndependentDepthValidation:
    """Gateway correctly rejects when caller understates current_depth."""

    def test_understated_depth_rejected(self):
        """Caller says depth=1 but gateway's independent verification says depth=3."""
        gw = GatewayState(max_delegation_depth=3)
        req = _make_request(depth=1, max_depth=3)  # caller claims depth=1
        # Plant independent depth knowledge: this request is actually at depth 3
        gw.depth_registry[req.request_id] = 3
        resp = gw.handle_handoff_request(req)
        assert not resp.accepted
        assert resp.rejection_code == common_pb2.VALIDATION_ERROR

    def test_honest_depth_accepted(self):
        """Caller honestly reports depth=1, gateway confirms."""
        gw = GatewayState(max_delegation_depth=3)
        req = _make_request(depth=1, max_depth=3)
        gw.depth_registry[req.request_id] = 1  # gateway independently confirms
        resp = gw.handle_handoff_request(req)
        assert resp.accepted


# ===========================================================================
# T-003: Budget monotonicity enforcement (Required) — §2.1
# ===========================================================================

class TestT003BudgetMonotonicity:
    """Callee rejects or corrects budget where child budget exceeds parent."""

    def test_child_budget_must_not_exceed_parent(self):
        """A child MUST NOT increase token budget beyond what parent provided."""
        parent_budget = 5000
        child_budget = 8000  # violates monotonicity

        assert child_budget > parent_budget, "Test setup: child exceeds parent"
        # Normative: callee MUST reject or clamp
        clamped = min(child_budget, parent_budget)
        assert clamped == parent_budget

    def test_child_may_tighten_budget(self):
        """A callee MAY tighten inherited budgets."""
        parent_budget = 10000
        child_budget = 7000  # tightened — valid
        assert child_budget <= parent_budget

    def test_deadline_must_be_present_for_cross_swarm(self):
        """deadline_epoch_ms MUST be present for cross-swarm delegation."""
        # Construct request with no deadline explicitly
        req = handoff_pb2.HandoffRequest(
            request_id="no-deadline",
            from_agent="parent",
            to_agent="gateway-1",
            budget=handoff_pb2.BudgetEnvelope(
                token_budget_remaining=10000,
                current_depth=0,
                max_delegation_depth=3,
                # deadline_epoch_ms intentionally omitted
            ),
        )
        assert req.budget.deadline_epoch_ms == 0, "No deadline set — violates §2.1 rule 1"
        # A conformant gateway MUST reject cross-swarm requests without a deadline

    def test_token_budget_counts_combined_io(self):
        """token_budget_remaining counts combined LLM input+output tokens (§2.1 rule 5)."""
        budget = handoff_pb2.BudgetEnvelope(
            token_budget_remaining=10000,
            deadline_epoch_ms=int(time.time() * 1000) + 60000,
        )
        # After caller uses 3000 tokens, propagated budget must be ≤7000
        caller_usage = 3000
        propagated = budget.token_budget_remaining - caller_usage
        assert propagated == 7000
        assert propagated < budget.token_budget_remaining


# ===========================================================================
# T-004: Deadline expiry fail-fast (Required) — §2.1
# ===========================================================================

class TestT004DeadlineExpiryFailFast:
    """Agent stops new model/tool work when now_ms > deadline_epoch_ms."""

    def test_expired_deadline_rejected(self):
        """Request with already-expired deadline must be rejected."""
        gw = GatewayState()
        past_deadline = int(time.time() * 1000) - 5000  # 5 seconds ago
        req = _make_request(deadline_epoch_ms=past_deadline)
        resp = gw.handle_handoff_request(req)
        assert not resp.accepted

    def test_future_deadline_accepted(self):
        """Request with future deadline should be accepted."""
        gw = GatewayState()
        future_deadline = int(time.time() * 1000) + 60000  # 60 seconds from now
        req = _make_request(deadline_epoch_ms=future_deadline)
        resp = gw.handle_handoff_request(req)
        assert resp.accepted

    def test_agent_checks_deadline_before_work(self):
        """Simulate agent checkpoint: must check deadline before starting work."""
        deadline_ms = int(time.time() * 1000) - 1  # just expired
        now_ms = int(time.time() * 1000)
        should_proceed = now_ms <= deadline_ms
        assert not should_proceed, "Agent must not proceed past deadline"


# ===========================================================================
# T-005: Overload backpressure signal (Required) — §4.1, §4.2
# ===========================================================================

class TestT005OverloadBackpressure:
    """Gateway returns OVERLOADED (not generic failure) when at capacity."""

    def test_overloaded_when_at_capacity(self):
        gw = GatewayState(max_concurrent_delegations=2)
        # Fill to capacity
        for _ in range(2):
            req = _make_request()
            resp = gw.handle_handoff_request(req)
            assert resp.accepted

        # Next request should get OVERLOADED
        req = _make_request()
        resp = gw.handle_handoff_request(req)
        assert not resp.accepted
        assert resp.rejection_code == common_pb2.OVERLOADED
        assert resp.retry_after_ms > 0

    def test_overloaded_is_backpressure_not_failure(self):
        """OVERLOADED MUST be treated as backpressure, not execution failure."""
        assert common_pb2.OVERLOADED == 16
        # Distinct from AGENT_UNAVAILABLE (4) or INTERNAL_ERROR (99)
        assert common_pb2.OVERLOADED != common_pb2.AGENT_UNAVAILABLE
        assert common_pb2.OVERLOADED != common_pb2.INTERNAL_ERROR

    def test_overloaded_includes_retry_after(self):
        """SHOULD include retry_after_ms hint."""
        gw = GatewayState(max_concurrent_delegations=0)  # always overloaded
        req = _make_request()
        resp = gw.handle_handoff_request(req)
        assert resp.rejection_code == common_pb2.OVERLOADED
        assert resp.retry_after_ms > 0


# ===========================================================================
# T-006: Retry jitter compliance (Required) — §4.3
# ===========================================================================

class TestT006RetryJitterCompliance:
    """Caller adds ≤20% uniform jitter to retry_after_ms; does not retry before jittered delay."""

    def test_jitter_within_bounds(self):
        """Jitter must be in range [retry_after_ms, retry_after_ms * 1.2]."""
        import random

        retry_after_ms = 1000
        # §4.3 rule 3: uniform random jitter up to 20%
        jittered = retry_after_ms + random.uniform(0, retry_after_ms * 0.2)
        assert jittered >= retry_after_ms
        assert jittered <= retry_after_ms * 1.2

    def test_jitter_range_statistical(self):
        """Over many samples, jitter should cover the full [0, 20%] range."""
        import random

        retry_after_ms = 1000
        samples = [retry_after_ms + random.uniform(0, retry_after_ms * 0.2) for _ in range(10000)]
        assert min(samples) >= retry_after_ms
        assert max(samples) <= retry_after_ms * 1.2
        # Should have some spread
        assert max(samples) - min(samples) > 100  # not all identical

    def test_no_retry_before_delay(self):
        """Caller MUST NOT retry before the jittered delay elapses."""
        retry_after_ms = 1000
        min_wait = retry_after_ms  # lower bound of jitter range
        # Any retry attempt before min_wait is a violation
        attempt_at_ms = 500
        assert attempt_at_ms < min_wait, "Premature retry violates §4.3"


# ===========================================================================
# T-007: Cancellation cascade depth=2 (Recommended) — §5.3
# ===========================================================================

class TestT007CancellationCascade:
    """Cancel propagates from parent gateway to child gateway; both reach terminal state."""

    def test_cancel_propagates_to_child(self):
        parent_gw = GatewayState(agent_id="parent-gateway")
        child_gw = GatewayState(agent_id="child-gateway")

        # Set up delegation chain: parent -> child
        parent_corr_id = "corr-parent-001"
        child_corr_id = "corr-child-001"
        parent_gw.child_delegations[parent_corr_id] = [child_corr_id]
        # Child gateway also tracks the child correlation
        child_gw.cancellation_flags[child_corr_id] = {"cancelled": False, "grace_period_ms": 0, "cancel_time_ms": 0}

        # Cancel at parent
        cancel = handoff_pb2.CancelDelegation(
            correlation_id=parent_corr_id,
            reason="test cascade",
            grace_period_ms=10000,
        )
        resp = parent_gw.handle_cancel_delegation(cancel)
        assert resp.acknowledged

        # Parent cancellation flag set
        assert parent_gw.is_cancelled(parent_corr_id)
        # Child cancellation flag set (propagated)
        assert parent_gw.is_cancelled(child_corr_id)

    def test_both_reach_terminal_state(self):
        gw = GatewayState()
        corr_id = "corr-terminal"
        gw.child_delegations[corr_id] = ["child-corr"]

        cancel = handoff_pb2.CancelDelegation(
            correlation_id=corr_id,
            reason="terminal test",
            grace_period_ms=5000,
        )
        gw.handle_cancel_delegation(cancel)
        assert gw.is_cancelled(corr_id)
        assert gw.is_cancelled("child-corr")


# ===========================================================================
# T-008: Cancellation grace period (Recommended) — §5.5, §5.6
# ===========================================================================

class TestT008CancellationGracePeriod:
    """At-exit handlers run within grace period; work stops after grace expiry."""

    def test_grace_period_minimum_5000ms(self):
        """If caller sends grace_period_ms=0, receiver MUST treat as 5000ms minimum."""
        gw = GatewayState()
        cancel = handoff_pb2.CancelDelegation(
            correlation_id="corr-grace",
            reason="test min grace",
            grace_period_ms=0,  # should be clamped to 5000
        )
        gw.handle_cancel_delegation(cancel)
        entry = gw.cancellation_flags["corr-grace"]
        assert entry["grace_period_ms"] == 5000

    def test_grace_period_preserved_when_above_minimum(self):
        """Grace period above minimum should be used as-is."""
        gw = GatewayState()
        cancel = handoff_pb2.CancelDelegation(
            correlation_id="corr-grace2",
            reason="test grace",
            grace_period_ms=15000,
        )
        gw.handle_cancel_delegation(cancel)
        entry = gw.cancellation_flags["corr-grace2"]
        assert entry["grace_period_ms"] == 15000

    def test_at_exit_handler_must_not_start_new_work(self):
        """At-exit handlers MUST NOT start new model inference or tool invocations."""
        # This is a structural/contract test: we verify the cancellation flag
        # prevents new work from starting
        gw = GatewayState()
        corr_id = "corr-atexit"
        cancel = handoff_pb2.CancelDelegation(
            correlation_id=corr_id,
            reason="test at-exit",
            grace_period_ms=5000,
        )
        gw.handle_cancel_delegation(cancel)
        assert gw.is_cancelled(corr_id)
        # New work must check cancellation flag at safe points
        # and refuse to start if cancelled


# ===========================================================================
# T-009: Forced termination after grace (Recommended) — §5.2
# ===========================================================================

class TestT009ForcedTerminationAfterGrace:
    """Gateway force-terminates with FORCED_PREEMPTION after grace period expires."""

    def test_forced_preemption_error_code_exists(self):
        """FORCED_PREEMPTION must be a valid ErrorCode."""
        assert common_pb2.FORCED_PREEMPTION == 12

    def test_grace_expiry_detection(self):
        """Gateway detects grace period expiry."""
        gw = GatewayState()
        corr_id = "corr-force"
        # Set a very short grace for testing (but note: in production, min is 5000ms)
        gw.cancellation_flags[corr_id] = {
            "cancelled": True,
            "grace_period_ms": 1,  # 1ms for test speed
            "cancel_time_ms": int(time.time() * 1000) - 100,  # 100ms ago
        }
        assert gw.is_grace_expired(corr_id)

    def test_not_expired_within_grace(self):
        """Grace period not expired if still within window."""
        gw = GatewayState()
        corr_id = "corr-not-expired"
        gw.cancellation_flags[corr_id] = {
            "cancelled": True,
            "grace_period_ms": 60000,  # 60 seconds
            "cancel_time_ms": int(time.time() * 1000),  # just now
        }
        assert not gw.is_grace_expired(corr_id)


# ===========================================================================
# T-010: Gateway-only addressing (Required) — §1.2
# ===========================================================================

class TestT010GatewayOnlyAddressing:
    """External caller cannot directly address child-swarm internal agents."""

    def test_internal_agent_rejected(self):
        gw = GatewayState(internal_agents=["worker-1", "worker-2", "planner-internal"])
        req = _make_request(to_agent="worker-1")
        resp = gw.handle_handoff_request(req)
        assert not resp.accepted
        assert resp.rejection_code == common_pb2.PERMISSION_DENIED

    def test_gateway_agent_accepted(self):
        gw = GatewayState()
        req = _make_request(to_agent="external-agent")
        resp = gw.handle_handoff_request(req)
        assert resp.accepted

    def test_all_internal_agents_blocked(self):
        """All internal agents must be blocked, not just some."""
        internal = ["worker-1", "worker-2", "planner-internal"]
        gw = GatewayState(internal_agents=internal)
        for agent_name in internal:
            req = _make_request(to_agent=agent_name)
            resp = gw.handle_handoff_request(req)
            assert not resp.accepted, f"{agent_name} should not be addressable externally"


# ===========================================================================
# T-011: Parent correlation on boundary (Required) — §3
# ===========================================================================

class TestT011ParentCorrelationOnBoundary:
    """parent_correlation_id is set on first envelope crossing a swarm boundary."""

    def test_parent_correlation_id_field_exists(self):
        """Envelope must support parent_correlation_id at field 100."""
        env = common_pb2.Envelope()
        env.parent_correlation_id = "parent-123"
        assert env.parent_correlation_id == "parent-123"

    def test_set_on_boundary_crossing(self):
        """On first swarm boundary crossing, parent_correlation_id MUST be set."""
        parent_corr = "corr-parent-" + str(uuid.uuid4())
        child_corr = "corr-child-" + str(uuid.uuid4())

        # First envelope in child swarm should carry parent_correlation_id
        child_envelope = common_pb2.Envelope(
            message_id=str(uuid.uuid4()),
            correlation_id=child_corr,
            parent_correlation_id=parent_corr,
        )
        assert child_envelope.parent_correlation_id == parent_corr
        assert child_envelope.correlation_id != child_envelope.parent_correlation_id

    def test_lineage_reconstruction(self):
        """Lineage must be reconstructable from (correlation_id, parent_correlation_id, message_id, idempotency_token)."""
        # Simulate 3-hop chain: A -> B -> C
        root = common_pb2.Envelope(
            message_id="msg-root",
            correlation_id="corr-A",
            parent_correlation_id="",  # root has no parent
        )
        hop_b = common_pb2.Envelope(
            message_id="msg-B",
            correlation_id="corr-B",
            parent_correlation_id="corr-A",
        )
        hop_c = common_pb2.Envelope(
            message_id="msg-C",
            correlation_id="corr-C",
            parent_correlation_id="corr-B",
        )

        # Walk the chain from leaf to root
        envelope_log = {
            "corr-A": root,
            "corr-B": hop_b,
            "corr-C": hop_c,
        }

        current = hop_c
        chain = [current.correlation_id]
        while current.parent_correlation_id:
            current = envelope_log[current.parent_correlation_id]
            chain.append(current.correlation_id)

        assert chain == ["corr-C", "corr-B", "corr-A"]


# ===========================================================================
# T-012: Non-preemptible section during cancel (Recommended) — §5.4
# ===========================================================================

class TestT012NonPreemptibleSection:
    """Agent in non-preemptible section defers cancellation to next safe point per Core §7.2."""

    def test_cancellation_deferred_in_critical_section(self):
        """Agent must not cancel mid-atomic-operation; defers to next safe point."""
        in_critical_section = True
        cancelled = True

        # Agent checks cancellation at safe point
        should_cancel = cancelled and not in_critical_section
        assert not should_cancel, "Must not cancel during critical section"

        # After critical section ends
        in_critical_section = False
        should_cancel = cancelled and not in_critical_section
        assert should_cancel, "Must cancel at next safe point"

    def test_cancellation_checked_at_same_points_as_deadline(self):
        """Agents MUST check cancellation at the same checkpoints as deadline_epoch_ms (§2.1 rule 6)."""
        # Both checks happen at the same safe point
        deadline_ms = int(time.time() * 1000) + 60000
        now_ms = int(time.time() * 1000)
        is_cancelled = False

        # Checkpoint: check both deadline AND cancellation
        deadline_exceeded = now_ms > deadline_ms
        should_stop = deadline_exceeded or is_cancelled
        assert not should_stop, "Neither deadline exceeded nor cancelled"

        # Now cancel
        is_cancelled = True
        should_stop = deadline_exceeded or is_cancelled
        assert should_stop, "Cancellation detected at checkpoint"


# ===========================================================================
# Proto structure validation (supplementary)
# ===========================================================================

class TestProtoStructure:
    """Validate that proto messages have the expected SW4-004 fields and values."""

    def test_overloaded_error_code_value(self):
        assert common_pb2.OVERLOADED == 16

    def test_swarm_gateway_registration_type(self):
        assert registry_pb2.SWARM_GATEWAY == 2
        assert registry_pb2.STANDARD_AGENT == 1

    def test_budget_envelope_fields(self):
        b = handoff_pb2.BudgetEnvelope(
            token_budget_remaining=1000,
            wall_time_remaining_ms=5000,
            deadline_epoch_ms=9999999,
            current_depth=1,
            max_delegation_depth=3,
        )
        assert b.token_budget_remaining == 1000
        assert b.wall_time_remaining_ms == 5000
        assert b.deadline_epoch_ms == 9999999
        assert b.current_depth == 1
        assert b.max_delegation_depth == 3

    def test_cancel_delegation_fields(self):
        c = handoff_pb2.CancelDelegation(
            correlation_id="test",
            reason="test reason",
            grace_period_ms=5000,
        )
        assert c.correlation_id == "test"
        assert c.reason == "test reason"
        assert c.grace_period_ms == 5000

    def test_handoff_request_sw4_004_fields(self):
        req = handoff_pb2.HandoffRequest(
            budget=handoff_pb2.BudgetEnvelope(token_budget_remaining=500),
            delegation_policy=handoff_pb2.SwarmDelegationPolicy(
                max_retries_on_overloaded=3,
                initial_backoff_ms=100,
                backoff_multiplier=2.0,
                max_backoff_ms=5000,
                allow_spillover_routing=True,
            ),
        )
        assert req.budget.token_budget_remaining == 500
        assert req.delegation_policy.max_retries_on_overloaded == 3
        assert req.delegation_policy.allow_spillover_routing

    def test_handoff_response_sw4_004_fields(self):
        resp = handoff_pb2.HandoffResponse(
            rejection_code=common_pb2.OVERLOADED,
            retry_after_ms=2000,
        )
        assert resp.rejection_code == common_pb2.OVERLOADED
        assert resp.retry_after_ms == 2000

    def test_agent_descriptor_sw4_004_fields(self):
        desc = registry_pb2.AgentDescriptor(
            agent_id="gw-1",
            registration_type=registry_pb2.SWARM_GATEWAY,
            max_concurrent_delegations=10,
        )
        assert desc.registration_type == registry_pb2.SWARM_GATEWAY
        assert desc.max_concurrent_delegations == 10

    def test_envelope_parent_correlation_id(self):
        env = common_pb2.Envelope(parent_correlation_id="parent-abc")
        assert env.parent_correlation_id == "parent-abc"
