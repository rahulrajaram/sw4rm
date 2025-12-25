from __future__ import annotations

from typing import Any


class SchedulerPolicyClient:
    """Client for Scheduler policy/profile/effective/evaluation RPCs.

    Requires generated stubs for `scheduler_policy.proto` and `policy.proto` in sw4rm.protos.
    """

    def __init__(self, channel: Any) -> None:
        self._channel = channel
        try:
            from sw4rm.protos import scheduler_policy_pb2, scheduler_policy_pb2_grpc, policy_pb2  # type: ignore
            self._pb2 = scheduler_policy_pb2
            self._policy_pb2 = policy_pb2
            self._stub = scheduler_policy_pb2_grpc.SchedulerPolicyServiceStub(channel)
        except Exception as e:  # pragma: no cover
            self._pb2 = None
            self._policy_pb2 = None
            self._stub = None

    def _require(self) -> None:
        if not self._stub:
            raise RuntimeError(
                "Protobuf stubs not generated for scheduler_policy. Run protoc to generate sw4rm/protos/*_pb2.py"
            )

    def set_negotiation_policy(self, policy: Any) -> Any:
        """Set the global negotiation policy.

        Configures the default policy used for all negotiations unless overridden
        by a specific profile. The policy defines constraints such as max rounds,
        score thresholds, token budgets, and HITL modes.

        Args:
            policy: NegotiationPolicy protobuf message with policy configuration.

        Returns:
            SetNegotiationPolicyResponse confirming the policy was set.

        Raises:
            RuntimeError: If protobuf stubs are not generated.
            grpc.RpcError: If the RPC call fails.

        Example:
            >>> from sw4rm.protos import policy_pb2
            >>> policy = policy_pb2.NegotiationPolicy(
            ...     max_rounds=10,
            ...     score_threshold=0.8,
            ...     hitl_mode="PauseBetweenRounds"
            ... )
            >>> client.set_negotiation_policy(policy)
        """
        self._require()
        req = self._pb2.SetNegotiationPolicyRequest(policy=policy)
        return self._stub.SetNegotiationPolicy(req)

    def get_negotiation_policy(self) -> Any:
        """Get the current global negotiation policy.

        Retrieves the active negotiation policy configuration that will be used
        as the default for new negotiations.

        Returns:
            GetNegotiationPolicyResponse containing the current NegotiationPolicy.

        Raises:
            RuntimeError: If protobuf stubs are not generated.
            grpc.RpcError: If the RPC call fails.

        Example:
            >>> response = client.get_negotiation_policy()
            >>> print(f"Max rounds: {response.policy.max_rounds}")
        """
        self._require()
        req = self._pb2.GetNegotiationPolicyRequest()
        return self._stub.GetNegotiationPolicy(req)

    def set_policy_profiles(self, profiles: list[Any]) -> Any:
        """Set available policy profiles.

        Policy profiles are named presets (e.g., LOW, MEDIUM, HIGH) that can be
        selected by agents or workflows. Each profile contains a complete
        EffectivePolicy configuration.

        Args:
            profiles: List of PolicyProfile protobuf messages to register.

        Returns:
            SetPolicyProfilesResponse confirming profiles were registered.

        Raises:
            RuntimeError: If protobuf stubs are not generated.
            grpc.RpcError: If the RPC call fails.

        Example:
            >>> from sw4rm.protos import policy_pb2
            >>> profiles = [
            ...     policy_pb2.PolicyProfile(
            ...         profile_id="low",
            ...         name="Low Intensity",
            ...         is_default=True
            ...     ),
            ...     policy_pb2.PolicyProfile(
            ...         profile_id="high",
            ...         name="High Intensity"
            ...     )
            ... ]
            >>> client.set_policy_profiles(profiles)
        """
        self._require()
        req = self._pb2.SetPolicyProfilesRequest(profiles=profiles)
        return self._stub.SetPolicyProfiles(req)

    def list_policy_profiles(self) -> Any:
        """List all available policy profiles.

        Returns all registered policy profiles that can be selected for
        negotiations.

        Returns:
            ListPolicyProfilesResponse with list of PolicyProfile messages.

        Raises:
            RuntimeError: If protobuf stubs are not generated.
            grpc.RpcError: If the RPC call fails.

        Example:
            >>> response = client.list_policy_profiles()
            >>> for profile in response.profiles:
            ...     print(f"{profile.name}: {profile.description}")
        """
        self._require()
        req = self._pb2.ListPolicyProfilesRequest()
        return self._stub.ListPolicyProfiles(req)

    def get_effective_policy(self, negotiation_id: str) -> Any:
        """Get the effective policy for a specific negotiation.

        Retrieves the resolved policy that is active for the given negotiation,
        including any profile selections and agent preference overrides.

        Args:
            negotiation_id: Unique identifier of the negotiation.

        Returns:
            GetEffectivePolicyResponse with the EffectivePolicy for this negotiation.

        Raises:
            RuntimeError: If protobuf stubs are not generated.
            grpc.RpcError: If the RPC call fails (e.g., negotiation not found).

        Example:
            >>> policy = client.get_effective_policy("neg-123")
            >>> print(f"Token budget: {policy.policy.negotiation.token_budget_per_round}")
        """
        self._require()
        req = self._pb2.GetEffectivePolicyRequest(negotiation_id=negotiation_id)
        return self._stub.GetEffectivePolicy(req)

    def submit_evaluation(self, negotiation_id: str, report: Any) -> Any:
        """Submit an evaluation report for a negotiation round.

        Agents submit evaluation reports after each round to record scores,
        deltas from previous versions, and qualitative feedback. The scheduler
        uses these reports to determine if the negotiation should continue or
        terminate.

        Args:
            negotiation_id: Unique identifier of the negotiation.
            report: EvaluationReport protobuf message with scores and feedback.

        Returns:
            SubmitEvaluationResponse confirming the report was recorded.

        Raises:
            RuntimeError: If protobuf stubs are not generated.
            grpc.RpcError: If the RPC call fails.

        Example:
            >>> from sw4rm.protos import policy_pb2
            >>> report = policy_pb2.EvaluationReport(
            ...     negotiation_id="neg-123",
            ...     round_number=2,
            ...     scores={"quality": 8.5},
            ...     summary="Good progress"
            ... )
            >>> client.submit_evaluation("neg-123", report)
        """
        self._require()
        req = self._pb2.SubmitEvaluationRequest(negotiation_id=negotiation_id, report=report)
        return self._stub.SubmitEvaluation(req)

    def hitl_action(self, negotiation_id: str, action: str, rationale: str = "") -> Any:
        """Record a human-in-the-loop action for a negotiation.

        When HITL mode is enabled in the policy, this method is used to record
        human decisions (approve, reject, continue, escalate) during the
        negotiation process.

        Args:
            negotiation_id: Unique identifier of the negotiation.
            action: HITL action to take (e.g., "approve", "reject", "continue").
            rationale: Optional human-readable explanation for the action.

        Returns:
            HitlActionResponse confirming the action was recorded.

        Raises:
            RuntimeError: If protobuf stubs are not generated.
            grpc.RpcError: If the RPC call fails.

        Example:
            >>> client.hitl_action(
            ...     negotiation_id="neg-123",
            ...     action="approve",
            ...     rationale="Manual review confirms security is adequate"
            ... )
        """
        self._require()
        req = self._pb2.HitlActionRequest(negotiation_id=negotiation_id, action=action, rationale=rationale)
        return self._stub.HitlAction(req)

