# SW4RM Elixir SDK

Elixir SDK for the SW4RM Agentic Protocol. Provides typed gRPC clients for all 13 protocol services, conformance-tested proto stubs, and local coordination primitives (NegotiationRoom, Delegation, Cancellation).

## Install

Add `sw4rm` to your `mix.exs` dependencies:

```elixir
def deps do
  [{:sw4rm, "~> 0.1.0"}]
end
```

## Quick Start

```elixir
alias Sw4rm.Clients.Registry

# Register an agent
{:ok, _} = Registry.register_agent(%{
  agent_id: "my-agent",
  name: "My Agent",
  capabilities: ["code_review"],
  communication_class: :STANDARD
})

# Send heartbeat
{:ok, _} = Registry.heartbeat(%{agent_id: "my-agent", state: :RUNNING})

# Open a negotiation room
alias Sw4rm.NegotiationRoom
alias Sw4rm.NegotiationRoom.{Proposal, Critique}

{:ok, room} = NegotiationRoom.start_link(room_id: "room-1")

NegotiationRoom.submit_proposal(room, %Proposal{
  artifact_id: "art-1",
  producer_id: "my-agent",
  artifact: "code payload"
})

NegotiationRoom.add_critique(room, "art-1", %Critique{
  critic_id: "reviewer-1",
  score: 8.5,
  passed: true
})
```

## Features

- 13 gRPC service clients (Registry, Router, Scheduler, Negotiation, NegotiationRoom, Handoff, Workflow, Tool, HITL, Worktree, Connector, Reasoning, Activity)
- SchedulerPolicy and Logging service clients
- Local NegotiationRoom GenServer with Store registry
- Quorum policies and vote collection timeouts (SW4-001)
- Per-service timeout profiles with clamping (SW4-002)
- Delegation and Cancellation coordination primitives
- Conformance test suite with protocol-level vectors
- Interceptor hooks on Transport.Client
- Envelope construction with Three-ID model (UUIDv4, correlation, idempotency)
- Provider-agnostic LLM client (Groq, Anthropic, Mock) with adaptive rate limiting

## LLM Client

The SDK includes a provider-agnostic LLM client layer with built-in rate
limiting. Supported providers: **Groq**, **Anthropic**, and **Mock** (for
tests).

### Creating a client

Use the factory to create a client without coupling to a specific provider:

```elixir
# Defaults to Mock (or the LLM_CLIENT_TYPE env var)
{:ok, {module, client}} = Sw4rm.LLM.Factory.create_llm_client()

# Explicit provider
{:ok, {module, client}} = Sw4rm.LLM.Factory.create_llm_client(client_type: "anthropic")

# Override the model
{:ok, {module, client}} = Sw4rm.LLM.Factory.create_llm_client(
  client_type: "groq",
  model: "llama-3.3-70b-versatile"
)
```

The return value is `{:ok, {module, client_or_pid}}`. Dispatch through the
module to stay provider-agnostic:

```elixir
{:ok, {mod, client}} = Sw4rm.LLM.Factory.create_llm_client()

{:ok, response} = mod.query("Summarise this diff.", client: client, system_prompt: "Be concise.")

IO.puts(response.content)
# response also contains :model, :usage (%{input_tokens, output_tokens}), :metadata
```

### Credentials

Each provider resolves credentials in order:

1. `:api_key` option passed to `new/1` (or forwarded through the factory)
2. Environment variable (`GROQ_API_KEY` / `ANTHROPIC_API_KEY`)
3. Dotfile in the home directory (`~/.groq` / `~/.anthropic`, plain text)

### Streaming

`stream_query/2` is defined by the `Sw4rm.LLM.Client` behaviour. Because the
SDK uses OTP's built-in `:httpc` (no external HTTP dependency), true
server-sent-event streaming is not supported. Both the Groq and Anthropic
clients fall back to returning the full response as a single-chunk list:

```elixir
{:ok, chunks} = mod.stream_query("Hello", client: client)
# chunks is a single-element list: ["full response text"]
full_text = Enum.join(chunks)
```

### Rate limiting

The `Sw4rm.LLM.RateLimiter` GenServer starts automatically in the application
supervision tree. All Groq and Anthropic clients use it by default -- no setup
required.

The limiter is adaptive: on a 429 response the token budget is reduced
(default factor 0.7); after a cooldown period and enough consecutive successes
the budget recovers (default factor 1.1) back to the base TPM.

To disable rate limiting for a specific client, pass `rate_limiter: nil`:

```elixir
{:ok, client} = Sw4rm.LLM.Groq.new(api_key: "gsk_...", rate_limiter: nil)
```

### Mock client for tests

```elixir
{:ok, {mod, mock}} = Sw4rm.LLM.Factory.create_llm_client(
  client_type: "mock",
  responses: ["Hello!", "World!"]
)

{:ok, r1} = mod.query("Hi", client: mock)
r1.content  #=> "Hello!"

Sw4rm.LLM.Mock.call_count(mock)  #=> 1
Sw4rm.LLM.Mock.call_history(mock) #=> [%{prompt: "Hi", ...}]
```

### Error tuples

All clients return `{:error, reason}` where `reason` is one of:

| Shape | Meaning |
|---|---|
| `{:authentication, msg}` | Invalid or missing credentials |
| `{:rate_limit, msg}` | API rate limit exceeded (HTTP 429) |
| `{:timeout, msg}` | Request timed out |
| `{:api_error, status, msg}` | Other HTTP/API error |
| `{:network, msg}` | Connection-level failure |

### Environment variables

| Variable | Default | Description |
|---|---|---|
| `LLM_CLIENT_TYPE` | `"mock"` | Default provider for `Factory.create_llm_client/1` |
| `LLM_DEFAULT_MODEL` | per-provider | Override the default model |
| `GROQ_API_KEY` | -- | Groq API key |
| `GROQ_DEFAULT_MODEL` | `"llama-3.3-70b-versatile"` | Groq model |
| `ANTHROPIC_API_KEY` | -- | Anthropic API key |
| `ANTHROPIC_DEFAULT_MODEL` | `"claude-sonnet-4-20250514"` | Anthropic model |
| `LLM_RATE_LIMIT_ENABLED` | `"1"` | Enable rate limiter (`"0"` to disable) |
| `LLM_RATE_LIMIT_TOKENS_PER_MIN` | `250000` | Token-bucket budget |
| `LLM_RATE_LIMIT_ADAPTIVE` | `"1"` | Enable adaptive throttling |

## Spec Compliance

- SW4RM Core Spec (all 13 services)
- SW4-001: Failure Semantics (quorum, vote collection timeout)
- SW4-002: Timeout Profiles (per-service timeouts)
- SW4-004: Connector Extension
- SW4-005: Reasoning Proxy Extension

## Running Tests

```bash
mix test
```

Or via Docker (no local Elixir required):

```bash
docker run --rm -v $(pwd)/../..:/app -w /app/sdks/ex_sdk elixir:1.16 bash -c \
  "mix local.hex --force && mix local.rebar --force && mix deps.get && mix test"
```

## Links

- [Operational Contracts](../docs/OPERATIONAL_CONTRACTS.md)
- [SW4RM Protocol Spec](../../documentation/protocol/)
- [JavaScript SDK](../js_sdk/README.md)
- [Python SDK](../py_sdk/README.md)
- [Rust SDK](../rust_sdk/README.md)

## License

MIT
