1. LLM Platform Milestone Context

1.1. Scope
This milestone defines the foundational model provider abstraction and the initial set of production-grade adapters for Anthropic Claude and OpenAI models. It includes streaming token support, function/tool invocation semantics, strict request/response schemas, retry policies, basic rate limiting, and smoke tests that validate end-to-end invocation through the Bee CLI. This scope excludes UI work beyond CLI ergonomics, evaluation frameworks, and integrations with open or local models, which will follow in subsequent milestones.

1.2. Objectives
The primary objective is to expose a single, stable trait in Rust that represents a large language model capable of text generation and tool-calling. A secondary objective is to supply concrete Claude and OpenAI adapters that satisfy the trait and conform to a uniform streaming and tool-call protocol. A tertiary objective is to provide precise error taxonomy and deterministic request signing and serialization to ensure reproducible tests and robust telemetry.

1.3. Deliverables
This milestone delivers a `ModelProvider` trait, a `CompletionRequest` and `CompletionResponse` schema with explicit states for streaming and tool calls, adapters for Anthropic Claude and OpenAI, a minimal in-process cache, idempotency keys for deduplication, and a suite of smoke tests covering request construction, streaming assembly, tool schema round-trips, and failure modes. It also delivers CLI flags to select providers and models and to enable streaming and tool calls.

1.4. Architecture and Interfaces
The system defines `ModelProvider` with synchronous and streaming interfaces. Requests specify model identifier, system instructions, messages with roles and content parts, tool specifications with JSON Schema, temperature and top-p sampling, max tokens, stop sequences, and idempotency key. Streaming yields typed events for textual deltas, tool call proposals, tool call confirmations, and finalization. Adapters translate the standardized request into provider-native payloads and canonicalize provider responses into the common response. Errors are normalized into a small set of categories: configuration, quota, transient network, server, schema, and abort. Rate limiting wraps the adapter with per-provider token buckets keyed by API key and model. An optional in-memory cache keyed by a content-addressed request hash enables response reuse for exact repeats.

1.5. Data Model
The request type contains model name, system message, ordered user/assistant messages, list of tool definitions with name, description, and JSON Schema for arguments, decoding parameters, and an idempotency key. The response type contains a finish reason, cumulative token usage, a list of tool call invocations with names and JSON arguments, and a final assistant message. Streaming yields an ordered sequence of events that, when reduced, equals the final response. All identifiers and timestamps use UTC and ISO 8601. All JSON argument payloads must validate against the declared schema before being emitted from the adapter.

1.6. Edge Cases and Failure Modes
The implementation must handle partial streams, duplicate events, reordered chunks, provider-specific content types such as images and tool results, and tool schema mismatches. Retries apply only to transient categories and must preserve idempotency keys to prevent double-charging. Timeouts result in an abort event with a well-formed partial transcript preserved for debugging. Authentication errors are non-retryable and produce actionable diagnostics. Schema violations surface as deterministic test failures rather than best-effort parsing.

1.7. Testing Strategy
Tests must cover serialization, deserialization, and schema validation for requests and responses, including tool specifications. Streaming tests must assemble deltas into final messages deterministically and assert equivalence with non-streaming completions for the same prompt. Adapters must be exercised with provider-recorded fixtures to avoid external dependencies in CI; fixtures should include success, rate limit, transient error, server error, malformed schema, and tool call flows. Property-based tests must fuzz JSON Schema and arguments to ensure robust validation. CLI smoke tests must invoke both providers in mock mode and validate stdout streaming and final outputs.

1.8. Non-Goals
This milestone does not implement open model or local inference adapters, prompt templating libraries, evaluation harnesses, or advanced caching beyond exact match memoization. It does not provide multimodal inputs beyond text and JSON tool calls.

1.9. Dependencies
This milestone depends only on existing CLI plumbing and telemetry scaffolding. Secrets management must provide API keys via environment variables or the secrets store once available. No message bus or scheduler features are required for the core functionality.

1.10. Migration and Rollout
The milestone introduces new modules behind feature flags to avoid breaking downstream crates. Default provider selection remains unset; users must specify provider and model explicitly. After validation, defaults may be established in a subsequent release.

1.11. Operational Considerations
Telemetry must record model, latency, token usage, and error category. Logs must avoid leaking secrets. Rate limits must be adjustable via environment variables. The adapters must degrade gracefully to non-streaming when terminals cannot handle incremental rendering.


1.12. Action Items (Next Steps)

- [ ] Finalize `ModelProvider` trait, request/response schemas, and streaming event model with tool-call protocol.
- [ ] Implement Anthropic and OpenAI adapters with strict JSON Schema validation and normalized error taxonomy.
- [ ] Add retry policy with idempotency keys and basic rate limiting; integrate optional exact-match cache.
- [ ] Create provider-recorded fixtures; implement streaming assembly parity tests and tool schema round-trips.
- [ ] Wire CLI flags to select provider/model, enable streaming and tools; add smoke tests using fixtures (no network).
- [ ] Integrate secrets resolver for `provider.*.api_key` by scope with clear override warnings.
- [ ] Emit telemetry (model, latency, tokens, error category) and document configuration/env knobs.
