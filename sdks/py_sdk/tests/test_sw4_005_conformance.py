"""
SW4-005 Spillover Routing — Conformance Test Scaffolding

Tests R-001 through R-012 per §11 of SW4-005-spillover-routing.md v0.2.0.
These tests validate normative protocol rules using in-process simulation of
caller and gateway behavior over real proto message types.
"""

from __future__ import annotations

import time
import uuid
from dataclasses import dataclass, field
from typing import Callable

from sw4rm.protos import common_pb2, handoff_pb2, registry_pb2


@dataclass
class FakeClock:
    """Deterministic clock for redirect-chain budget/deadline tests."""

    now_ms: int = 1_700_000_000_000

    def now(self) -> int:
        return self.now_ms

    def advance(self, delta_ms: int) -> None:
        self.now_ms += max(delta_ms, 0)


@dataclass
class PeerRecord:
    """Registry/health state used by the gateway redirect simulator."""

    descriptor: registry_pb2.AgentDescriptor
    state: int = common_pb2.RUNNING
    last_heartbeat_ms: int = 0
    cooldown_until_ms: int = 0


@dataclass
class SpilloverGatewaySimulator:
    """Minimal overloaded gateway simulator with SW4-005 redirect behavior."""

    agent_id: str = "gateway-a"
    capabilities: tuple[str, ...] = ("plan", "execute")
    max_concurrent_delegations: int = 1
    active_delegations: int = 0
    retry_after_ms: int = 1000
    liveness_threshold_ms: int = 30_000
    now_ms_fn: Callable[[], int] = lambda: int(time.time() * 1000)
    peers: list[PeerRecord] = field(default_factory=list)
    _rr_cursor: int = 0

    def handle_handoff_request(
        self, request: handoff_pb2.HandoffRequest
    ) -> handoff_pb2.HandoffResponse:
        overloaded = self.active_delegations >= self.max_concurrent_delegations
        if not overloaded:
            self.active_delegations += 1
            return handoff_pb2.HandoffResponse(
                request_id=request.request_id,
                accepted=True,
                accepting_agent=self.agent_id,
            )

        if not request.delegation_policy.allow_spillover_routing:
            return self._overloaded_response(request.request_id)

        target = self._choose_redirect_target()
        if not target:
            return self._overloaded_response(request.request_id)

        return handoff_pb2.HandoffResponse(
            request_id=request.request_id,
            accepted=False,
            rejection_reason="Gateway at capacity; redirect to healthy peer",
            rejection_code=common_pb2.REDIRECT,
            redirect_to_agent_id=target,
        )

    def _choose_redirect_target(self) -> str:
        eligible = [peer for peer in self.peers if self._is_eligible(peer)]
        healthy = [peer for peer in eligible if self._is_healthy(peer)]
        if not healthy:
            return ""

        idx = self._rr_cursor % len(healthy)
        self._rr_cursor += 1
        return healthy[idx].descriptor.agent_id

    def _is_eligible(self, peer: PeerRecord) -> bool:
        desc = peer.descriptor
        if desc.registration_type != registry_pb2.SWARM_GATEWAY:
            return False
        if desc.agent_id == self.agent_id:
            return False
        return tuple(desc.capabilities) == tuple(self.capabilities)

    def _is_healthy(self, peer: PeerRecord) -> bool:
        now_ms = self.now_ms_fn()
        if peer.cooldown_until_ms > now_ms:
            return False
        if now_ms - peer.last_heartbeat_ms > self.liveness_threshold_ms:
            return False
        if peer.state in {
            common_pb2.INITIALIZING,
            common_pb2.FAILED_STATE,
            common_pb2.SHUTTING_DOWN,
        }:
            return False
        return True

    def _overloaded_response(self, request_id: str) -> handoff_pb2.HandoffResponse:
        return handoff_pb2.HandoffResponse(
            request_id=request_id,
            accepted=False,
            rejection_reason="Gateway at capacity",
            rejection_code=common_pb2.OVERLOADED,
            retry_after_ms=self.retry_after_ms,
        )


@dataclass
class SendResult:
    """Single simulated handoff send attempt."""

    response: handoff_pb2.HandoffResponse
    elapsed_ms: int = 0


@dataclass
class AttemptTrace:
    """Observability for assertions across simulated hops."""

    visited_agents: list[str] = field(default_factory=list)
    responses: list[handoff_pb2.HandoffResponse] = field(default_factory=list)
    wall_time_history_ms: list[int] = field(default_factory=list)
    envelopes: list[common_pb2.Envelope] = field(default_factory=list)


@dataclass
class RedirectCallerSimulator:
    """Caller-side redirect/overload behavior per SW4-005 + SW4-004."""

    clock: FakeClock

    def execute(
        self,
        request: handoff_pb2.HandoffRequest,
        envelope: common_pb2.Envelope,
        send_fn: Callable[[str, handoff_pb2.HandoffRequest, common_pb2.Envelope], SendResult],
    ) -> tuple[handoff_pb2.HandoffResponse, AttemptTrace]:
        current_target = request.to_agent
        trace = AttemptTrace(visited_agents=[current_target])

        policy = request.delegation_policy
        effective_max_redirects = int(policy.max_redirects or 2)
        redirect_hops = 0
        overloaded_retries = 0

        while True:
            if self._deadline_or_walltime_exhausted(request):
                return self._deadline_exhausted_response(request.request_id), trace

            hop_envelope = self._hop_envelope(envelope)
            trace.envelopes.append(hop_envelope)
            result = send_fn(current_target, request, hop_envelope)
            response = result.response
            elapsed_ms = max(int(result.elapsed_ms), 0)

            self.clock.advance(elapsed_ms)
            request.budget.wall_time_remaining_ms = max(
                int(request.budget.wall_time_remaining_ms) - elapsed_ms,
                0,
            )

            trace.responses.append(response)
            trace.wall_time_history_ms.append(int(request.budget.wall_time_remaining_ms))

            if response.accepted:
                return response, trace

            if response.rejection_code == common_pb2.REDIRECT:
                if redirect_hops >= effective_max_redirects:
                    return response, trace
                if self._deadline_or_walltime_exhausted(request):
                    return self._deadline_exhausted_response(request.request_id), trace

                target = response.redirect_to_agent_id
                if not target or target in trace.visited_agents:
                    return handoff_pb2.HandoffResponse(
                        request_id=request.request_id,
                        accepted=False,
                        rejection_reason="Redirect loop or invalid redirect target",
                        rejection_code=common_pb2.VALIDATION_ERROR,
                    ), trace

                redirect_hops += 1
                current_target = target
                request.to_agent = target
                trace.visited_agents.append(target)
                continue

            if response.rejection_code == common_pb2.OVERLOADED:
                if overloaded_retries >= int(policy.max_retries_on_overloaded):
                    return response, trace

                wait_ms = max(int(response.retry_after_ms), 0)
                if wait_ms > int(request.budget.wall_time_remaining_ms):
                    return response, trace
                if request.budget.deadline_epoch_ms > 0 and (
                    self.clock.now() + wait_ms > int(request.budget.deadline_epoch_ms)
                ):
                    return response, trace

                self.clock.advance(wait_ms)
                request.budget.wall_time_remaining_ms = max(
                    int(request.budget.wall_time_remaining_ms) - wait_ms,
                    0,
                )
                overloaded_retries += 1
                continue

            return response, trace

    def _deadline_or_walltime_exhausted(self, request: handoff_pb2.HandoffRequest) -> bool:
        if int(request.budget.wall_time_remaining_ms) <= 0:
            return True
        return (
            int(request.budget.deadline_epoch_ms) > 0
            and self.clock.now() > int(request.budget.deadline_epoch_ms)
        )

    def _hop_envelope(self, base: common_pb2.Envelope) -> common_pb2.Envelope:
        return common_pb2.Envelope(
            message_id=str(uuid.uuid4()),
            producer_id=base.producer_id,
            correlation_id=base.correlation_id,
            idempotency_token=base.idempotency_token,
            parent_correlation_id=base.parent_correlation_id,
        )

    @staticmethod
    def _deadline_exhausted_response(request_id: str) -> handoff_pb2.HandoffResponse:
        return handoff_pb2.HandoffResponse(
            request_id=request_id,
            accepted=False,
            rejection_reason="Delegation deadline exhausted while following redirects",
            rejection_code=common_pb2.ACK_TIMEOUT,
        )


def _make_peer(
    *,
    agent_id: str,
    capabilities: tuple[str, ...],
    registration_type: int = registry_pb2.SWARM_GATEWAY,
    state: int = common_pb2.RUNNING,
    last_heartbeat_ms: int,
    cooldown_until_ms: int = 0,
) -> PeerRecord:
    return PeerRecord(
        descriptor=registry_pb2.AgentDescriptor(
            agent_id=agent_id,
            registration_type=registration_type,
            capabilities=list(capabilities),
        ),
        state=state,
        last_heartbeat_ms=last_heartbeat_ms,
        cooldown_until_ms=cooldown_until_ms,
    )


def _make_request(
    *,
    to_agent: str = "gateway-a",
    allow_spillover: bool = True,
    max_redirects: int = 0,
    max_retries_on_overloaded: int = 2,
    now_ms: int,
    wall_time_remaining_ms: int = 60_000,
    deadline_offset_ms: int = 60_000,
) -> handoff_pb2.HandoffRequest:
    return handoff_pb2.HandoffRequest(
        request_id=str(uuid.uuid4()),
        from_agent="caller",
        to_agent=to_agent,
        reason="sw4-005 conformance",
        budget=handoff_pb2.BudgetEnvelope(
            token_budget_remaining=10_000,
            wall_time_remaining_ms=wall_time_remaining_ms,
            deadline_epoch_ms=now_ms + deadline_offset_ms,
            current_depth=0,
            max_delegation_depth=3,
        ),
        delegation_policy=handoff_pb2.SwarmDelegationPolicy(
            max_retries_on_overloaded=max_retries_on_overloaded,
            allow_spillover_routing=allow_spillover,
            max_redirects=max_redirects,
        ),
    )


def _make_envelope() -> common_pb2.Envelope:
    return common_pb2.Envelope(
        message_id=str(uuid.uuid4()),
        producer_id="caller",
        correlation_id="corr-123",
        idempotency_token="idem-xyz",
        parent_correlation_id="parent-corr",
    )


# ===========================================================================
# R-001: Spillover disabled => gateway never emits REDIRECT
# ===========================================================================

class TestR001SpilloverDisabled:
    def test_gateway_returns_overloaded_not_redirect(self):
        clock = FakeClock()
        gw = SpilloverGatewaySimulator(
            max_concurrent_delegations=1,
            active_delegations=1,
            now_ms_fn=clock.now,
        )
        gw.peers.append(
            _make_peer(
                agent_id="gateway-b",
                capabilities=gw.capabilities,
                last_heartbeat_ms=clock.now(),
            )
        )

        req = _make_request(allow_spillover=False, now_ms=clock.now())
        resp = gw.handle_handoff_request(req)
        assert not resp.accepted
        assert resp.rejection_code == common_pb2.OVERLOADED
        assert resp.rejection_code != common_pb2.REDIRECT


# ===========================================================================
# R-002: Eligible peer exists + gateway overloaded => REDIRECT
# ===========================================================================

class TestR002EligiblePeerRedirect:
    def test_gateway_emits_redirect_to_eligible_peer(self):
        clock = FakeClock()
        gw = SpilloverGatewaySimulator(
            max_concurrent_delegations=1,
            active_delegations=1,
            now_ms_fn=clock.now,
        )
        gw.peers.append(
            _make_peer(
                agent_id="gateway-b",
                capabilities=gw.capabilities,
                last_heartbeat_ms=clock.now(),
            )
        )

        req = _make_request(allow_spillover=True, now_ms=clock.now())
        resp = gw.handle_handoff_request(req)
        assert not resp.accepted
        assert resp.rejection_code == common_pb2.REDIRECT
        assert resp.redirect_to_agent_id == "gateway-b"


# ===========================================================================
# R-003: No healthy eligible peers => OVERLOADED (not REDIRECT)
# ===========================================================================

class TestR003NoHealthyEligiblePeers:
    def test_gateway_falls_back_to_overloaded(self):
        clock = FakeClock()
        gw = SpilloverGatewaySimulator(
            max_concurrent_delegations=1,
            active_delegations=1,
            now_ms_fn=clock.now,
        )
        gw.peers.extend(
            [
                _make_peer(
                    agent_id="non-gateway",
                    capabilities=gw.capabilities,
                    registration_type=registry_pb2.STANDARD_AGENT,
                    last_heartbeat_ms=clock.now(),
                ),
                _make_peer(
                    agent_id="wrong-capabilities",
                    capabilities=("other",),
                    last_heartbeat_ms=clock.now(),
                ),
                _make_peer(
                    agent_id="stale-peer",
                    capabilities=gw.capabilities,
                    last_heartbeat_ms=clock.now() - 100_000,
                ),
            ]
        )

        req = _make_request(allow_spillover=True, now_ms=clock.now())
        resp = gw.handle_handoff_request(req)
        assert not resp.accepted
        assert resp.rejection_code == common_pb2.OVERLOADED
        assert resp.rejection_code != common_pb2.REDIRECT


# ===========================================================================
# R-004: Redirect response shape
# ===========================================================================

class TestR004RedirectResponseShape:
    def test_redirect_shape_is_protocol_valid(self):
        clock = FakeClock()
        gw = SpilloverGatewaySimulator(
            max_concurrent_delegations=1,
            active_delegations=1,
            now_ms_fn=clock.now,
        )
        gw.peers.append(
            _make_peer(
                agent_id="gateway-b",
                capabilities=gw.capabilities,
                last_heartbeat_ms=clock.now(),
            )
        )

        req = _make_request(allow_spillover=True, now_ms=clock.now())
        resp = gw.handle_handoff_request(req)
        assert not resp.accepted
        assert resp.rejection_code == common_pb2.REDIRECT
        assert resp.redirect_to_agent_id == "gateway-b"
        assert resp.retry_after_ms == 0


# ===========================================================================
# R-005: max_redirects=0 => effective redirect bound is 2
# ===========================================================================

class TestR005DefaultRedirectBound:
    def test_zero_max_redirects_behaves_as_two(self):
        clock = FakeClock()
        caller = RedirectCallerSimulator(clock=clock)
        req = _make_request(max_redirects=0, now_ms=clock.now(), to_agent="gateway-a")

        routing = {
            "gateway-a": "gateway-b",
            "gateway-b": "gateway-c",
            "gateway-c": "gateway-d",
        }

        def send_fn(
            target: str, _req: handoff_pb2.HandoffRequest, _env: common_pb2.Envelope
        ) -> SendResult:
            return SendResult(
                response=handoff_pb2.HandoffResponse(
                    request_id=_req.request_id,
                    accepted=False,
                    rejection_code=common_pb2.REDIRECT,
                    redirect_to_agent_id=routing[target],
                ),
                elapsed_ms=5,
            )

        resp, trace = caller.execute(req, _make_envelope(), send_fn)
        assert resp.rejection_code == common_pb2.REDIRECT
        assert trace.visited_agents == ["gateway-a", "gateway-b", "gateway-c"]
        assert len(trace.responses) == 3


# ===========================================================================
# R-006: explicit max_redirects bound is enforced
# ===========================================================================

class TestR006ExplicitRedirectBound:
    def test_caller_stops_at_explicit_bound(self):
        clock = FakeClock()
        caller = RedirectCallerSimulator(clock=clock)
        req = _make_request(max_redirects=1, now_ms=clock.now(), to_agent="gateway-a")

        def send_fn(
            target: str, _req: handoff_pb2.HandoffRequest, _env: common_pb2.Envelope
        ) -> SendResult:
            next_target = "gateway-b" if target == "gateway-a" else "gateway-c"
            return SendResult(
                response=handoff_pb2.HandoffResponse(
                    request_id=_req.request_id,
                    accepted=False,
                    rejection_code=common_pb2.REDIRECT,
                    redirect_to_agent_id=next_target,
                ),
                elapsed_ms=7,
            )

        resp, trace = caller.execute(req, _make_envelope(), send_fn)
        assert resp.rejection_code == common_pb2.REDIRECT
        assert trace.visited_agents == ["gateway-a", "gateway-b"]
        assert len(trace.responses) == 2


# ===========================================================================
# R-007: stale/non-serving peers are excluded from redirect selection
# ===========================================================================

class TestR007HealthFiltering:
    def test_only_healthy_peer_is_selected(self):
        clock = FakeClock()
        gw = SpilloverGatewaySimulator(
            max_concurrent_delegations=1,
            active_delegations=1,
            now_ms_fn=clock.now,
        )
        gw.peers.extend(
            [
                _make_peer(
                    agent_id="peer-stale",
                    capabilities=gw.capabilities,
                    last_heartbeat_ms=clock.now() - 120_000,
                ),
                _make_peer(
                    agent_id="peer-initializing",
                    capabilities=gw.capabilities,
                    state=common_pb2.INITIALIZING,
                    last_heartbeat_ms=clock.now(),
                ),
                _make_peer(
                    agent_id="peer-failed",
                    capabilities=gw.capabilities,
                    state=common_pb2.FAILED_STATE,
                    last_heartbeat_ms=clock.now(),
                ),
                _make_peer(
                    agent_id="peer-healthy",
                    capabilities=gw.capabilities,
                    last_heartbeat_ms=clock.now(),
                ),
            ]
        )

        req = _make_request(now_ms=clock.now(), allow_spillover=True)
        resp = gw.handle_handoff_request(req)
        assert resp.rejection_code == common_pb2.REDIRECT
        assert resp.redirect_to_agent_id == "peer-healthy"


# ===========================================================================
# R-008: round-robin fairness across healthy peers
# ===========================================================================

class TestR008RoundRobinFairness:
    def test_redirect_targets_rotate(self):
        clock = FakeClock()
        gw = SpilloverGatewaySimulator(
            max_concurrent_delegations=0,
            active_delegations=0,
            now_ms_fn=clock.now,
        )
        gw.peers.extend(
            [
                _make_peer(
                    agent_id="peer-1",
                    capabilities=gw.capabilities,
                    last_heartbeat_ms=clock.now(),
                ),
                _make_peer(
                    agent_id="peer-2",
                    capabilities=gw.capabilities,
                    last_heartbeat_ms=clock.now(),
                ),
                _make_peer(
                    agent_id="peer-3",
                    capabilities=gw.capabilities,
                    last_heartbeat_ms=clock.now(),
                ),
            ]
        )

        req = _make_request(now_ms=clock.now(), allow_spillover=True)
        seen = []
        for _ in range(6):
            req.request_id = str(uuid.uuid4())
            resp = gw.handle_handoff_request(req)
            seen.append(resp.redirect_to_agent_id)

        assert seen == ["peer-1", "peer-2", "peer-3", "peer-1", "peer-2", "peer-3"]


# ===========================================================================
# R-009: wall-time budget decreases across redirect hops
# ===========================================================================

class TestR009WallTimeBudgetDeduction:
    def test_wall_time_budget_is_deducted_per_redirect_hop(self):
        clock = FakeClock()
        caller = RedirectCallerSimulator(clock=clock)
        req = _make_request(
            max_redirects=3,
            now_ms=clock.now(),
            to_agent="gateway-a",
            wall_time_remaining_ms=100,
            deadline_offset_ms=1_000,
        )

        calls = 0

        def send_fn(
            target: str, _req: handoff_pb2.HandoffRequest, _env: common_pb2.Envelope
        ) -> SendResult:
            nonlocal calls
            calls += 1
            if target == "gateway-a":
                return SendResult(
                    response=handoff_pb2.HandoffResponse(
                        request_id=_req.request_id,
                        accepted=False,
                        rejection_code=common_pb2.REDIRECT,
                        redirect_to_agent_id="gateway-b",
                    ),
                    elapsed_ms=30,
                )
            if target == "gateway-b":
                return SendResult(
                    response=handoff_pb2.HandoffResponse(
                        request_id=_req.request_id,
                        accepted=False,
                        rejection_code=common_pb2.REDIRECT,
                        redirect_to_agent_id="gateway-c",
                    ),
                    elapsed_ms=20,
                )
            return SendResult(
                response=handoff_pb2.HandoffResponse(
                    request_id=_req.request_id,
                    accepted=True,
                    accepting_agent="gateway-c",
                ),
                elapsed_ms=0,
            )

        resp, trace = caller.execute(req, _make_envelope(), send_fn)
        assert resp.accepted
        assert calls == 3
        assert trace.wall_time_history_ms[:2] == [70, 50]
        assert req.budget.wall_time_remaining_ms == 50


# ===========================================================================
# R-010: deadline bound enforced when stricter than wall-time
# ===========================================================================

class TestR010DeadlineEnforcement:
    def test_caller_aborts_when_deadline_is_exceeded(self):
        clock = FakeClock()
        caller = RedirectCallerSimulator(clock=clock)
        req = _make_request(
            max_redirects=3,
            now_ms=clock.now(),
            to_agent="gateway-a",
            wall_time_remaining_ms=500,
            deadline_offset_ms=40,
        )

        attempts = 0

        def send_fn(
            _target: str, _req: handoff_pb2.HandoffRequest, _env: common_pb2.Envelope
        ) -> SendResult:
            nonlocal attempts
            attempts += 1
            return SendResult(
                response=handoff_pb2.HandoffResponse(
                    request_id=_req.request_id,
                    accepted=False,
                    rejection_code=common_pb2.REDIRECT,
                    redirect_to_agent_id="gateway-b",
                ),
                elapsed_ms=50,
            )

        resp, trace = caller.execute(req, _make_envelope(), send_fn)
        assert not resp.accepted
        assert resp.rejection_code == common_pb2.ACK_TIMEOUT
        assert attempts == 1
        assert len(trace.responses) == 1


# ===========================================================================
# R-011: metadata continuity across redirect hops
# ===========================================================================

class TestR011MetadataContinuity:
    def test_correlation_and_idempotency_are_preserved(self):
        clock = FakeClock()
        caller = RedirectCallerSimulator(clock=clock)
        req = _make_request(max_redirects=3, now_ms=clock.now(), to_agent="gateway-a")
        envelope = _make_envelope()

        def send_fn(
            target: str, _req: handoff_pb2.HandoffRequest, env: common_pb2.Envelope
        ) -> SendResult:
            if target == "gateway-a":
                return SendResult(
                    response=handoff_pb2.HandoffResponse(
                        request_id=_req.request_id,
                        accepted=False,
                        rejection_code=common_pb2.REDIRECT,
                        redirect_to_agent_id="gateway-b",
                    )
                )
            if target == "gateway-b":
                return SendResult(
                    response=handoff_pb2.HandoffResponse(
                        request_id=_req.request_id,
                        accepted=False,
                        rejection_code=common_pb2.REDIRECT,
                        redirect_to_agent_id="gateway-c",
                    )
                )
            return SendResult(
                response=handoff_pb2.HandoffResponse(
                    request_id=_req.request_id,
                    accepted=True,
                    accepting_agent="gateway-c",
                )
            )

        resp, trace = caller.execute(req, envelope, send_fn)
        assert resp.accepted
        assert len(trace.envelopes) == 3
        assert all(e.correlation_id == envelope.correlation_id for e in trace.envelopes)
        assert all(e.idempotency_token == envelope.idempotency_token for e in trace.envelopes)
        assert len({e.message_id for e in trace.envelopes}) == 3


# ===========================================================================
# R-012: legacy gateway fallback to SW4-004 overloaded retries
# ===========================================================================

class TestR012BackwardCompatibility:
    def test_legacy_overloaded_path_uses_sw4_004_retry_behavior(self):
        clock = FakeClock()
        caller = RedirectCallerSimulator(clock=clock)
        req = _make_request(
            now_ms=clock.now(),
            allow_spillover=True,
            max_retries_on_overloaded=2,
            max_redirects=3,
            to_agent="legacy-gateway",
            wall_time_remaining_ms=1_000,
            deadline_offset_ms=1_000,
        )

        attempts = 0

        def send_fn(
            _target: str, _req: handoff_pb2.HandoffRequest, _env: common_pb2.Envelope
        ) -> SendResult:
            nonlocal attempts
            attempts += 1
            if attempts <= 2:
                return SendResult(
                    response=handoff_pb2.HandoffResponse(
                        request_id=_req.request_id,
                        accepted=False,
                        rejection_code=common_pb2.OVERLOADED,
                        retry_after_ms=10,
                    ),
                    elapsed_ms=1,
                )
            return SendResult(
                response=handoff_pb2.HandoffResponse(
                    request_id=_req.request_id,
                    accepted=True,
                    accepting_agent="legacy-gateway",
                ),
                elapsed_ms=1,
            )

        resp, _trace = caller.execute(req, _make_envelope(), send_fn)
        assert resp.accepted
        assert attempts == 3


# ===========================================================================
# Proto structure validation (supplementary)
# ===========================================================================

class TestProtoStructureSW4005:
    def test_redirect_error_code_value(self):
        assert common_pb2.REDIRECT == 20

    def test_handoff_response_redirect_field(self):
        resp = handoff_pb2.HandoffResponse(redirect_to_agent_id="gateway-z")
        assert resp.redirect_to_agent_id == "gateway-z"

    def test_swarm_delegation_policy_max_redirects_field(self):
        policy = handoff_pb2.SwarmDelegationPolicy(max_redirects=4)
        assert policy.max_redirects == 4
