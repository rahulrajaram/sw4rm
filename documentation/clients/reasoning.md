# 6.8. Reasoning Client

The Reasoning Client talks to the `sw4rm.reasoning.ReasoningProxy` service. Use it to:

- Check whether two task scopes can safely execute in parallel.
- Evaluate competing proposals during negotiation or debate.
- Summarize multi-segment text streams with a token budget.

## 6.8.1. Service Overview

The service exposes three RPCs:

- `CheckParallelism(ParallelismCheckRequest) -> ParallelismCheckResponse`
- `EvaluateDebate(DebateEvaluateRequest) -> DebateEvaluateResponse`
- `Summarize(SummarizeRequest) -> SummarizeResponse`

## 6.8.2. Constructors

### Python

`ReasoningClient(channel: grpc.Channel)`

- `channel`: A gRPC channel connected to the ReasoningProxy endpoint.

### JavaScript/TypeScript

`new ReasoningClient(options: ClientOptions)`

- `options.address`: `host:port` for the ReasoningProxy endpoint.
- Optional: `deadlineMs`, `retry`, `userAgent`, `interceptors`, `errorMapper`.

### Rust

`ReasoningClient::new(endpoint: &str) -> Result<ReasoningClient>`

- `endpoint`: Full gRPC URL (for example, `http://host:port`).

## 6.8.3. Key Methods

### `check_parallelism`

**Python**
`check_parallelism(scope_a: str, scope_b: str) -> ParallelismCheckResponse`

**JavaScript/TypeScript**
`checkParallelism(scopeA: string, scopeB: string): Promise<{ confidence_score: number; notes?: string }>`

**Rust**
`check_parallelism(scope_a: &str, scope_b: &str) -> Result<ParallelismCheckResponse>`

**Response fields**

- `confidence_score` (float): Confidence that the scopes are parallel (0-1).
- `notes` (string): Short explanation.

### `evaluate_debate`

**Python**
`evaluate_debate(negotiation_id: str, proposal_a: str, proposal_b: str, intensity: str = "low")`

**JavaScript/TypeScript**
`evaluateDebate(negotiationId: string, proposalA: string, proposalB: string, intensity?: string)`

**Rust**
`evaluate_debate(negotiation_id: &str, proposal_a: &str, proposal_b: &str, intensity: &str)`

**Response fields**

- `confidence_score` (float): Confidence in the evaluation (0-1).
- `notes` (string): Rationale or evaluation details.

### `summarize`

**Python**
`summarize(session_id: str, segments: list[dict], max_tokens: int = 256, mode: str = "rolling")`

**Rust**
`summarize(session_id: &str, segments: Vec<(String, String, i64, String)>, max_tokens: u32, mode: &str)`

**Request fields**

- `session_id`: Unique identifier for the summarization session.
- `segments`: List of text segments with `(kind, content, seq, at)` or dict keys in Python.
- `max_tokens`: Token budget for the summary.
- `mode`: Summarization strategy (for example, `rolling` or `full`).

**Response fields**

- `summary` (string): Generated summary.
- `tokens` (int): Token count used.
- `cost_cents` (float): Billed cost in cents.
- `model` (string): Model identifier.

Note: The JavaScript/TypeScript client currently exposes `checkParallelism` and
`evaluateDebate` only. Use the Python or Rust client for `Summarize` until the JS
API adds that method.

## 6.8.4. Usage Examples

=== "Python"
    ```python
    import grpc
    from sw4rm.clients import ReasoningClient

    channel = grpc.insecure_channel("REASONING_HOST:REASONING_PORT")
    client = ReasoningClient(channel)

    parallel = client.check_parallelism(
        "Run unit tests for the SDK",
        "Update documentation for ReasoningClient",
    )
    print(parallel.confidence_score, parallel.notes)

    debate = client.evaluate_debate(
        negotiation_id="neg-001",
        proposal_a="Use rolling deploys",
        proposal_b="Use blue/green deploys",
        intensity="medium",
    )
    print(debate.confidence_score, debate.notes)

    summary = client.summarize(
        session_id="summ-001",
        segments=[
            {"kind": "user", "content": "We need a release plan.", "seq": 1, "at": "t1"},
            {"kind": "assistant", "content": "Drafting a release plan now.", "seq": 2, "at": "t2"},
        ],
        max_tokens=200,
        mode="rolling",
    )
    print(summary.summary)
    ```

=== "JavaScript/TypeScript"
    ```ts
    import { ReasoningClient } from '@sw4rm/js-sdk';

    const client = new ReasoningClient({
      address: 'REASONING_HOST:REASONING_PORT',
      deadlineMs: 20000,
    });

    const parallel = await client.checkParallelism(
      'Analyze data pipeline',
      'Update runbook docs',
    );
    console.log(parallel.confidence_score, parallel.notes);

    const debate = await client.evaluateDebate(
      'neg-001',
      'Use rolling deploys',
      'Use blue/green deploys',
      'medium',
    );
    console.log(debate.confidence_score, debate.notes);
    ```

=== "Rust"
    ```rust
    use sw4rm_sdk::clients::ReasoningClient;

    #[tokio::main]
    async fn main() -> sw4rm_sdk::Result<()> {
        let mut client = ReasoningClient::new("http://REASONING_HOST:REASONING_PORT").await?;

        let parallel = client
            .check_parallelism("Run tests", "Update docs")
            .await?;
        println!("score={} notes={}", parallel.confidence_score, parallel.notes);

        let debate = client
            .evaluate_debate(
                "neg-001",
                "Use rolling deploys",
                "Use blue/green deploys",
                "medium",
            )
            .await?;
        println!("score={} notes={}", debate.confidence_score, debate.notes);

        let summary = client
            .summarize(
                "summ-001",
                vec![
                    ("user".to_string(), "Need a release plan.".to_string(), 1, "t1".to_string()),
                    ("assistant".to_string(), "Drafting now.".to_string(), 2, "t2".to_string()),
                ],
                200,
                "rolling",
            )
            .await?;
        println!("summary={}", summary.summary);

        Ok(())
    }
    ```

## 6.8.5. Error Handling

- Python raises `RuntimeError` if protobuf stubs are missing. Run `make protos`.
- JavaScript/TypeScript methods reject with gRPC errors (wrapped as `Sw4rmError`).
- Rust returns `Result<T>`; handle transport errors and status codes via `?`.
