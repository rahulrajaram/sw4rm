# 6.9. Scheduler Policy Client

The Scheduler Policy Client talks to the `sw4rm.scheduler.SchedulerPolicyService` service. Use it to:

- Define the global negotiation policy guardrails.
- Register and list named policy profiles.
- Fetch the effective policy for a negotiation.
- Submit evaluation reports and HITL actions.

## 6.9.1. Service Overview

The service exposes seven RPCs:

- `SetNegotiationPolicy(SetNegotiationPolicyRequest) -> SetNegotiationPolicyResponse`
- `GetNegotiationPolicy(GetNegotiationPolicyRequest) -> GetNegotiationPolicyResponse`
- `SetPolicyProfiles(SetPolicyProfilesRequest) -> SetPolicyProfilesResponse`
- `ListPolicyProfiles(ListPolicyProfilesRequest) -> ListPolicyProfilesResponse`
- `GetEffectivePolicy(GetEffectivePolicyRequest) -> GetEffectivePolicyResponse`
- `SubmitEvaluation(SubmitEvaluationRequest) -> SubmitEvaluationResponse`
- `HitlAction(HitlActionRequest) -> HitlActionResponse`

Policy message types live in `policy.proto` (`NegotiationPolicy`, `PolicyProfile`,
`EvaluationReport`, and `EffectivePolicy`).

## 6.9.2. Constructors

### Python

`SchedulerPolicyClient(channel: grpc.Channel)`

- `channel`: A gRPC channel connected to the SchedulerPolicyService endpoint.

### JavaScript/TypeScript

`new SchedulerPolicyClient(options: ClientOptions)`

- `options.address`: `host:port` for the SchedulerPolicyService endpoint.
- Optional: `deadlineMs`, `retry`, `userAgent`, `interceptors`, `errorMapper`.

### Rust

`SchedulerPolicyClient::new(endpoint: &str) -> Result<SchedulerPolicyClient>`

- `endpoint`: Full gRPC URL (for example, `http://host:port`).

## 6.9.3. Key Methods

### `set_negotiation_policy`

**Python**
`set_negotiation_policy(policy: NegotiationPolicy) -> SetNegotiationPolicyResponse`

**JavaScript/TypeScript**
`setWagglePolicy(policy: any): Promise<{ ok: boolean; reason?: string }>`

**Rust**
`set_negotiation_policy(policy: NegotiationPolicy) -> Result<bool>`

**Response fields**

- `ok` (bool): Whether the policy was accepted.
- `reason` (string): Optional rejection reason.

### `get_negotiation_policy`

**Python**
`get_negotiation_policy() -> GetNegotiationPolicyResponse`

**JavaScript/TypeScript**
`getWagglePolicy(): Promise<{ policy?: any }>`

**Rust**
`get_negotiation_policy() -> Result<Option<NegotiationPolicy>>`

**Response fields**

- `policy` (NegotiationPolicy): Current global policy.

### `set_policy_profiles`

**Python**
`set_policy_profiles(profiles: list[PolicyProfile]) -> SetPolicyProfilesResponse`

**JavaScript/TypeScript**
`setPolicyProfiles(profiles: any[]): Promise<{ ok: boolean; reason?: string }>`

**Rust**
`set_policy_profiles(profiles: Vec<PolicyProfile>) -> Result<bool>`

**Response fields**

- `ok` (bool): Whether the profiles were accepted.
- `reason` (string): Optional rejection reason.

### `list_policy_profiles`

**Python**
`list_policy_profiles() -> ListPolicyProfilesResponse`

**JavaScript/TypeScript**
`listPolicyProfiles(): Promise<{ profiles: any[] }>`

**Rust**
`list_policy_profiles() -> Result<Vec<PolicyProfile>>`

**Response fields**

- `profiles` (PolicyProfile[]): All registered profiles.

### `get_effective_policy`

**Python**
`get_effective_policy(negotiation_id: str) -> GetEffectivePolicyResponse`

**JavaScript/TypeScript**
`getEffectivePolicy(negotiationId: string): Promise<{ effective?: any }>`

**Rust**
`get_effective_policy(negotiation_id: &str) -> Result<Option<EffectivePolicy>>`

**Response fields**

- `effective` (EffectivePolicy): Effective policy for the negotiation.

### `submit_evaluation`

**Python**
`submit_evaluation(negotiation_id: str, report: EvaluationReport) -> SubmitEvaluationResponse`

**JavaScript/TypeScript**
`submitEvaluation(negotiationId: string, report: any): Promise<{ accepted: boolean; reason?: string }>`

**Rust**
`submit_evaluation(negotiation_id: &str, report: EvaluationReport) -> Result<bool>`

**Response fields**

- `accepted` (bool): Whether the report was accepted.
- `reason` (string): Optional rejection reason.

### `hitl_action`

**Python**
`hitl_action(negotiation_id: str, action: str, rationale: str = "") -> HitlActionResponse`

**JavaScript/TypeScript**
`hitlAction(negotiationId: string, action: string, rationale?: string): Promise<{ ok: boolean; reason?: string }>`

**Rust**
`hitl_action(negotiation_id: &str, action: &str, rationale: &str) -> Result<bool>`

**Response fields**

- `ok` (bool): Whether the action was accepted.
- `reason` (string): Optional rejection reason.

Note: The JavaScript/TypeScript client currently uses `setWagglePolicy` and
`getWagglePolicy` naming for the negotiation policy RPCs. These map to the
`SetNegotiationPolicy` and `GetNegotiationPolicy` RPCs on the service.

## 6.9.4. Usage Examples

=== "Python"
    ```python
    import grpc
    from sw4rm.clients import SchedulerPolicyClient
    from sw4rm.protos import policy_pb2

    channel = grpc.insecure_channel("SCHEDULER_HOST:SCHEDULER_PORT")
    client = SchedulerPolicyClient(channel)

    policy = policy_pb2.NegotiationPolicy(
        max_rounds=5,
        score_threshold=0.8,
        diff_tolerance=0.1,
        round_timeout_ms=60000,
        token_budget_per_round=8000,
        oscillation_limit=3,
        hitl=policy_pb2.NegotiationPolicy.Hitl(mode="PauseBetweenRounds"),
    )
    client.set_negotiation_policy(policy)

    profiles = [
        policy_pb2.PolicyProfile(name="LOW", policy=policy),
        policy_pb2.PolicyProfile(name="HIGH", policy=policy_pb2.NegotiationPolicy(max_rounds=10)),
    ]
    client.set_policy_profiles(profiles)

    response = client.get_effective_policy("neg-001")
    print(response.effective.policy.max_rounds)

    report = policy_pb2.EvaluationReport(
        from_agent="reviewer-1",
        deterministic_score=0.92,
        llm_confidence=0.85,
        notes="Strong proposal with minor edits",
    )
    client.submit_evaluation("neg-001", report)

    client.hitl_action("neg-001", "approve", "Manual review completed")
    ```

=== "JavaScript/TypeScript"
    ```ts
    import { SchedulerPolicyClient } from '@sw4rm/js-sdk';

    const client = new SchedulerPolicyClient({
      address: 'SCHEDULER_HOST:SCHEDULER_PORT',
      deadlineMs: 20000,
    });

    await client.setWagglePolicy({
      max_rounds: 5,
      score_threshold: 0.8,
      diff_tolerance: 0.1,
      round_timeout_ms: 60000,
    });

    const profiles = await client.listPolicyProfiles();
    console.log(profiles.profiles.length);

    const effective = await client.getEffectivePolicy('neg-001');
    console.log(effective.effective);

    await client.submitEvaluation('neg-001', {
      from_agent: 'reviewer-1',
      deterministic_score: 0.92,
      notes: 'Strong proposal with minor edits',
    });

    await client.hitlAction('neg-001', 'approve', 'Manual review completed');
    ```

=== "Rust"
    ```rust
    use sw4rm_sdk::clients::SchedulerPolicyClient;
    use sw4rm_sdk::proto::sw4rm::policy::{EvaluationReport, NegotiationPolicy, PolicyProfile};

    #[tokio::main]
    async fn main() -> sw4rm_sdk::Result<()> {
        let mut client = SchedulerPolicyClient::new("http://SCHEDULER_HOST:SCHEDULER_PORT").await?;

        let policy = NegotiationPolicy {
            max_rounds: 5,
            score_threshold: 0.8,
            diff_tolerance: 0.1,
            ..Default::default()
        };
        client.set_negotiation_policy(policy.clone()).await?;

        let profiles = vec![
            PolicyProfile { name: "LOW".to_string(), policy: Some(policy.clone()) },
            PolicyProfile { name: "HIGH".to_string(), policy: Some(policy) },
        ];
        client.set_policy_profiles(profiles).await?;

        let effective = client.get_effective_policy("neg-001").await?;
        println!("effective={:?}", effective);

        let report = EvaluationReport {
            from_agent: "reviewer-1".to_string(),
            deterministic_score: 0.92,
            llm_confidence: 0.85,
            notes: "Strong proposal".to_string(),
            ..Default::default()
        };
        client.submit_evaluation("neg-001", report).await?;

        client.hitl_action("neg-001", "approve", "Manual review completed").await?;

        Ok(())
    }
    ```

## 6.9.5. Error Handling

- Python raises `RuntimeError` if protobuf stubs are missing. Run `make protos`.
- JavaScript/TypeScript methods reject with gRPC errors (wrapped as `Sw4rmError`).
- Rust returns `Result<T>`; handle transport errors and status codes via `?`.
