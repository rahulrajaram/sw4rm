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

    def set_waggle_policy(self, policy: Any) -> Any:
        self._require()
        req = self._pb2.SetWagglePolicyRequest(policy=policy)
        return self._stub.SetWagglePolicy(req)

    def get_waggle_policy(self) -> Any:
        self._require()
        req = self._pb2.GetWagglePolicyRequest()
        return self._stub.GetWagglePolicy(req)

    def set_policy_profiles(self, profiles: list[Any]) -> Any:
        self._require()
        req = self._pb2.SetPolicyProfilesRequest(profiles=profiles)
        return self._stub.SetPolicyProfiles(req)

    def list_policy_profiles(self) -> Any:
        self._require()
        req = self._pb2.ListPolicyProfilesRequest()
        return self._stub.ListPolicyProfiles(req)

    def get_effective_policy(self, negotiation_id: str) -> Any:
        self._require()
        req = self._pb2.GetEffectivePolicyRequest(negotiation_id=negotiation_id)
        return self._stub.GetEffectivePolicy(req)

    def submit_evaluation(self, negotiation_id: str, report: Any) -> Any:
        self._require()
        req = self._pb2.SubmitEvaluationRequest(negotiation_id=negotiation_id, report=report)
        return self._stub.SubmitEvaluation(req)

    def hitl_action(self, negotiation_id: str, action: str, rationale: str = "") -> Any:
        self._require()
        req = self._pb2.HitlActionRequest(negotiation_id=negotiation_id, action=action, rationale=rationale)
        return self._stub.HitlAction(req)

