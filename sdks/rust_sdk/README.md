# SW4RM Rust SDK

Reference Rust SDK for the SW4RM Agentic Protocol. This is one of five SDKs in this repository (Python, Rust, JavaScript, Elixir, Common Lisp) and provides high-performance gRPC clients and runtime utilities for building distributed autonomous agents.

## Features

- **Type-safe gRPC clients** for all SW4RM protocol services
- **Async/await runtime** built on Tokio for high concurrency
- **Cooperative preemption** support for graceful agent shutdown
- **Envelope helpers** for message construction and parsing
- **Built-in logging and tracing** via tracing crate
- **Configurable endpoints** with sensible defaults
- **Production-ready** error handling and resource management
- **CONTROL helpers** and content-types for CONTROL-only flows (scheduler command v1, agent report v1)
- **LLM client abstraction** with Groq, Anthropic, and mock backends (feature `llm`)

## Install

Add to your `Cargo.toml`:

```toml
[dependencies]
sw4rm-sdk = "0.6.0"
tokio = { version = "1.0", features = ["full"] }
```

## Quick Start with Working Services

🎉 **NEW**: Complete working example with services included! You can now run a full SW4RM setup locally.

### 1. Start the Services

**Option A: Python Services (Recommended for getting started)**
```bash
cd ../../examples/reference-services/
./start_services_local.sh
```

**Option B: Rust Services**
```bash
cd ../../examples/reference-services/rust/
cargo run --bin start-services
```

### 2. Run the Echo Agent

```bash
cargo run --example echo_agent
```

You should see:
```
✅ Registered agent successfully
🚀 Starting message loop for echo-agent
```

### 3. Test the Setup

```bash
# In another terminal
cd ../../examples/reference-services/
python test_complete_setup.py
```

This will send a test message that your agent will receive and process!

### Basic Agent Example

```rust
use sw4rm_sdk::*;
use async_trait::async_trait;

struct EchoAgent {
    config: AgentConfig,
    preemption: PreemptionManager,
}

impl EchoAgent {
    fn new(config: AgentConfig) -> Self {
        Self {
            config,
            preemption: PreemptionManager::new(),
        }
    }
}

#[async_trait]
impl Agent for EchoAgent {
    async fn on_message(&mut self, envelope: EnvelopeData) -> Result<()> {
        if let Ok(text) = envelope.string_payload() {
            println!("Echo: {}", text);
        }
        Ok(())
    }

    fn config(&self) -> &AgentConfig {
        &self.config
    }

    fn preemption_manager(&self) -> &PreemptionManager {
        &self.preemption
    }
}

#[tokio::main]
async fn main() -> Result<()> {
    let config = AgentConfig::new(
        "echo-agent-1".to_string(),
        "Echo Agent".to_string()
    );
    
    let agent = EchoAgent::new(config.clone());
    let mut runtime = AgentRuntime::new(config);
    
    runtime.run(agent).await
}
```

## Architecture

The SDK is organized into several key modules:

- **`clients/`** - Type-safe gRPC clients for each service
- **`runtime/`** - Agent runtime and preemption management
- **`envelope/`** - Message envelope builders and utilities
- **`config/`** - Configuration structures and defaults
- **`types/`** - Common types and utilities
- **`error/`** - Error types and result handling
- **`llm/`** - Provider-agnostic LLM client (feature-gated)

## Protocol Services

The SDK provides clients for all SW4RM protocol services:

- **Registry** - Agent registration and discovery
- **Router** - Message routing and delivery
- **Scheduler** - Task scheduling and preemption
- **HITL** - Human-in-the-loop decisions
- **Worktree** - Code repository management
- **Tool** - Tool execution and management
- **Connector** - Tool provider registration
- **Negotiation** - Multi-agent negotiation
- **Reasoning** - Parallelism and debate evaluation
- **Logging** - Distributed logging and telemetry

## Configuration

Configure service endpoints via the `Endpoints` struct:

```rust
use sw4rm_sdk::*;

let endpoints = Endpoints {
    registry: "http://localhost:50051".to_string(),
    router: "http://localhost:50052".to_string(),
    // ... other services
    ..Default::default()
};

let config = AgentConfig::new("my-agent".to_string(), "My Agent".to_string())
    .with_endpoints(endpoints);
```

## Links

- Top-level README (overview and API): `../../README.md`
- Quickstart for running local services: `../../QUICKSTART.md`
- Python SDK: `../py_sdk/README.md`
- JavaScript SDK: `../js_sdk/README.md`

## Building from Source

The SDK requires protobuf compilation. Ensure you have the protocol buffer compiler installed:

```bash
# On macOS
brew install protobuf

# On Ubuntu/Debian
sudo apt-get install protobuf-compiler

# On other systems, see: https://grpc.io/docs/protoc-installation/
```

Then build:

```bash
cargo build --release
```

## Examples

See the `examples/` directory for more comprehensive usage examples including:

- Basic echo agent
- Tool integration
- HITL workflows  
- Multi-agent negotiation
- Preemption handling

### Example: CONTROL scheduler command

```rust
use sw4rm_sdk::{EnvelopeBuilder, constants, control::{SchedulerCommandV1, SchedulerStage, CT_SCHEDULER_COMMAND_V1}};

let cmd = SchedulerCommandV1::new(SchedulerStage::Run)
    .with_input(serde_json::json!({"repo":"demo"}));
let payload = cmd.to_bytes().unwrap();

let env = EnvelopeBuilder::new("frontend-agent".into(), constants::message_type::CONTROL)
    .with_payload(payload)
    .with_content_type(CT_SCHEDULER_COMMAND_V1.to_string())
    .build();
// send `env` via Router client
```

## LLM Client

The SDK includes a provider-agnostic LLM client behind the `llm` feature flag.
Supported backends: **Groq** (OpenAI-compatible), **Anthropic** (Claude), and a
**Mock** client for testing.

### Enable the feature

```toml
[dependencies]
sw4rm-sdk = { version = "0.6.0", features = ["llm"] }
tokio = { version = "1.0", features = ["full"] }
```

### Create a client with the factory

`create_llm_client` resolves the provider from its arguments, the
`LLM_CLIENT_TYPE` environment variable, or falls to `"mock"` as the default:

```rust,no_run
use sw4rm_sdk::llm::{create_llm_client, LlmClient};

// Detect provider from LLM_CLIENT_TYPE env var (defaults to "mock")
let client = create_llm_client(None, None).unwrap();

// Explicit provider
let client = create_llm_client(Some("groq"), None).unwrap();

// Explicit provider + model override
let client = create_llm_client(Some("anthropic"), Some("claude-opus-4-20250514")).unwrap();
```

### Query example (async)

```rust,no_run
use sw4rm_sdk::llm::{create_llm_client, LlmClient, LlmResponse};

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let client = create_llm_client(Some("groq"), None)?;

    let response: LlmResponse = client.query(
        "Summarize the latest build results.",
        Some("You are a concise CI assistant."),
        4096,   // max_tokens
        0.7,    // temperature
        None,   // model_override (use provider default)
    ).await?;

    println!("Model: {}", response.model);
    println!("Reply: {}", response.content);
    println!("Tokens: {:?}", response.usage);
    Ok(())
}
```

### Credential resolution

Each provider resolves its API key using the same three-step chain:

| Priority | Source | Groq | Anthropic |
|----------|--------|------|-----------|
| 1 | Constructor `api_key` param | `GroqClient::new(Some("sk-..."), ...)` | `AnthropicClient::new(Some("sk-..."), ...)` |
| 2 | Environment variable | `GROQ_API_KEY` | `ANTHROPIC_API_KEY` |
| 3 | Dotfile in home directory | `~/.groq` | `~/.anthropic` |

If none of the three sources yields a key, the client returns
`LlmError::Authentication` at construction time.

### Rate limiting

Rate limiting is automatic and process-global. All LLM clients share a single
token-bucket that refills at 250,000 tokens per minute (Groq free-tier default).
When a provider returns HTTP 429 the bucket adaptively reduces its budget; after
a cooldown period and enough consecutive successes it recovers toward the
original baseline.

No application code is required -- the rate limiter runs transparently inside
every `query` and `stream_query` call.

### Environment variables

| Variable | Default | Description |
|----------|---------|-------------|
| `LLM_CLIENT_TYPE` | `"mock"` | Provider for `create_llm_client`: `"groq"`, `"anthropic"`, `"mock"` |
| `LLM_DEFAULT_MODEL` | (provider default) | Override default model for any provider |
| `GROQ_API_KEY` | -- | Groq API key |
| `GROQ_DEFAULT_MODEL` | `llama-3.3-70b-versatile` | Groq default model |
| `ANTHROPIC_API_KEY` | -- | Anthropic API key |
| `ANTHROPIC_DEFAULT_MODEL` | `claude-sonnet-4-20250514` | Anthropic default model |
| `LLM_RATE_LIMIT_ENABLED` | `"1"` | Enable/disable the global rate limiter |
| `LLM_RATE_LIMIT_TOKENS_PER_MIN` | `250000` | Token budget per minute |
| `LLM_RATE_LIMIT_ADAPTIVE` | `"1"` | Enable adaptive throttle (reduce on 429, recover on success) |

### Mock client for tests

The mock client needs no API key and no feature flag:

```rust
use sw4rm_sdk::llm::{MockLlmClient, LlmClient};

# async fn run() -> Result<(), Box<dyn std::error::Error>> {
let client = MockLlmClient::new(
    "test-model".to_string(),
    vec!["First response".to_string(), "Second response".to_string()],
);

let r1 = client.query("a", None, 4096, 1.0, None).await?;
let r2 = client.query("b", None, 4096, 1.0, None).await?;
assert_eq!(r1.content, "First response");
assert_eq!(r2.content, "Second response");
assert_eq!(client.call_count(), 2);
# Ok(())
# }
```

## Testing

Run the test suite:

```bash
cargo test
```

For integration tests with a running SW4RM cluster:

```bash
cargo test --features integration-tests
```

## Operational Contracts

For production deployments, see the **[Operational Contracts](../docs/OPERATIONAL_CONTRACTS.md)** documentation, which defines:

- Connection timeouts and keep-alive settings
- Retry policies and error handling
- Data consistency guarantees
- Idempotency contracts
- State persistence guarantees

These are protocol-level contracts that all SW4RM SDKs honor.

## Contributing

This SDK follows the SW4RM protocol specification. When contributing:

1. Ensure protobuf compatibility
2. Maintain async/await patterns
3. Add comprehensive error handling
4. Include tests for new features
5. Update documentation

## License

MIT License - see LICENSE file for details.
