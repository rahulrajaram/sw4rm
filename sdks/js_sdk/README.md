# SW4RM JavaScript SDK

Reference JavaScript SDK for the SW4RM Agentic Protocol. This is one of five SDKs in this repository (Python, Rust, JavaScript, Elixir, Common Lisp). The 0.7.0 development tree includes the complete canonical wire interface and local coordination helpers.

## Complete wire interface (0.7.0 development target)

`ProtocolClient` provides `call()` and `stream()` for all 15 canonical services
and 57 RPCs. Use proto field names, byte arrays, and decimal strings for full-range
64-bit integers. The client rejects unsafe integer inputs before serialization.
The local handoff, workflow and negotiation-room helpers retain their local APIs.

See the [SDK parity contract](../../documentation/sdk-parity.md) for message
representations, portable idempotency, local-only helpers and verification.


## Install

```bash
npm install @sw4rm/js-sdk
```

## Running services

SDKs connect to separately running services. Follow the [Python reference service
setup](../py_sdk/reference-services/README.md) for the services implemented in this repository, and
use the [SDK parity examples](../../documentation/sdk-parity.md) for the complete
wire interface. A generated client does not imply that its server is implemented.

## Quick Start

```typescript
import { RegistryClient } from '@sw4rm/js-sdk';

const client = new RegistryClient({ address: 'localhost:50052' });

// Register agent
await client.registerAgent({
  agent_id: 'my-agent',
  name: 'My Agent',
  description: 'Example agent implementation',
  capabilities: ['example'],
  communication_class: 'STANDARD',
  modalities_supported: ['application/json'],
  reasoning_connectors: ['http://localhost:8080'],
});

// Send heartbeat
await client.heartbeat('my-agent', 'RUNNING');

// Deregister
await client.deregisterAgent('my-agent', 'Done');
```

## Implementation Status

- ✅ Base gRPC client infrastructure
- ✅ RegistryClient (agent registration, heartbeat, deregistration)
- ✅ LLM clients (Groq, Anthropic, Mock) with adaptive rate limiting
- ✅ TypeScript type definitions
- ✅ Unit tests
- Complete canonical RPC access through `ProtocolClient`

## License

MIT
## Builds

This package ships dual builds for maximum compatibility:

- ESM: `dist/esm` (modern Node, bundlers)
- CommonJS: `dist/cjs` (require)
- Types: `dist/types` for TypeScript and editors

## Usage

JavaScript (CommonJS):

```js
const { RouterClient, buildEnvelope, MessageType } = require('@sw4rm/js-sdk');
```

ESM/TypeScript:

```ts
import { RouterClient, buildEnvelope, MessageType } from '@sw4rm/js-sdk';
```

## Quick example: route + ACK

```ts
import { RouterClient, buildEnvelope, MessageType, ACKLifecycleManager, createResilientIncomingStream, sendMessageWithAck } from '@sw4rm/js-sdk';

const router = new RouterClient({ address: 'localhost:50051' });
const stream = createResilientIncomingStream(router, 'agent-123');
const ack = new ACKLifecycleManager();

const env = buildEnvelope({
  producer_id: 'agent-123',
  message_type: MessageType.DATA,
  payload: new TextEncoder().encode(JSON.stringify({ hello: 'world' })),
  content_type: 'application/json',
});

// Example ACK extractor if server sends acknowledgements as envelopes
const extractor = (item: { msg: any }) => ({ ackFor: item.msg?.ack_for_message_id, stage: item.msg?.ack_stage });
await sendMessageWithAck(router, stream as any, env, ack, extractor, { receivedTimeoutMs: 10000 });
```

`streamIncoming` yields `StreamItem` objects with the envelope in `msg` and a
lossless router delivery sequence in `seq` (represented as a string for int64
compatibility). A consumer should acknowledge the item after its side effect:

```ts
stream.on('data', async (item) => {
  try {
    await processMessage(item.msg);
    await router.ackStreamItem('agent-123', item);
  } catch {
    await router.ackStreamItem('agent-123', item, true); // permanent failure
  }
});
```

Unacknowledged rows can be redelivered by the router after its lease expires;
use the envelope's `idempotency_token` to make consumer-side processing safe.

## Quorum policy

The runtime-neutral quorum helpers mirror the Python policy contract. They
support minimum votes, a ceiling-based fraction, and require-all rules, with
explicit fail-closed, abstain, and available-votes actions:

```ts
import { MinimumFraction, QuorumPolicy, evaluateQuorum } from '@sw4rm/js-sdk';

const outcome = evaluateQuorum(votes, requestedCritics,
  new QuorumPolicy(new MinimumFraction(0.5), 'fail_closed'));
if (!outcome.met) console.log(outcome.action);
```

## CONTROL helpers

When using CONTROL-only orchestration flows, use the provided content-types and encoder:

```ts
import { buildEnvelope, MessageType } from '@sw4rm/js-sdk';
import { CT_SCHEDULER_COMMAND_V1, encodeSchedulerCommandV1 } from '@sw4rm/js-sdk';

const payload = encodeSchedulerCommandV1({ stage: 'run', input: { repo: 'demo' } });
const env = buildEnvelope({
  producer_id: 'frontend-agent',
  message_type: MessageType.CONTROL,
  payload,
  content_type: CT_SCHEDULER_COMMAND_V1,
});
// send `env` via RouterClient
```

## Persistence

```ts
import { ActivityBuffer, ACKLifecycleManager, RuntimePersistence } from '@sw4rm/js-sdk';
const buf = new ActivityBuffer();
const acks = new ACKLifecycleManager();
const persist = RuntimePersistence.json('.sw4rm', buf, acks, { autosaveMs: 5000 });
await persist.load();
persist.startAutosave();
```

## LLM Client

The SDK includes a provider-agnostic LLM client abstraction. Agents can query
language models through a unified interface without coupling to a specific vendor.

### Import

```ts
import {
  createLlmClient,
  GroqClient,
  AnthropicClient,
  MockLlmClient,
} from '@sw4rm/js-sdk';
```

### Factory

The `createLlmClient` factory selects a provider based on explicit options or
environment variables. When nothing is specified it defaults to the mock client,
so tests never hit a real API.

```ts
// Auto-detect from LLM_CLIENT_TYPE env var (default: "mock")
const client = createLlmClient();

// Explicit provider
const groq = createLlmClient({ clientType: 'groq' });
const claude = createLlmClient({
  clientType: 'anthropic',
  model: 'claude-sonnet-4-20250514',
});

// Override API key and timeout
const custom = createLlmClient({
  clientType: 'groq',
  apiKey: 'gsk_...',
  timeoutMs: 60_000,
});
```

### Credential resolution

Each provider resolves its API key in this order:

1. `apiKey` constructor / factory parameter
2. Environment variable (`GROQ_API_KEY` or `ANTHROPIC_API_KEY`)
3. Dotfile in the home directory (`~/.groq` or `~/.anthropic`, plain text, one line)

If none of these are set the constructor throws `LlmAuthenticationError`.

### Basic query

```ts
import { createLlmClient } from '@sw4rm/js-sdk';

const client = createLlmClient({ clientType: 'groq' });

const response = await client.query(
  'Analyze this task and suggest next steps.',
  {
    systemPrompt: 'You are a helpful task-analysis agent.',
    maxTokens: 2048,
    temperature: 0.7,
  },
);

console.log(response.content);       // generated text
console.log(response.model);         // e.g. "llama-3.3-70b-versatile"
console.log(response.usage);         // { input_tokens, output_tokens }
```

### Streaming

`streamQuery` returns an `AsyncGenerator<string>` that yields text chunks as
they arrive over SSE.

```ts
const client = createLlmClient({ clientType: 'anthropic' });

for await (const chunk of client.streamQuery('Write a status report.', {
  systemPrompt: 'You are a concise technical writer.',
})) {
  process.stdout.write(chunk);
}
```

### Mock client for testing

`MockLlmClient` never makes network calls. It records every query so tests
can assert on prompts, token counts, and call order.

```ts
import { MockLlmClient } from '@sw4rm/js-sdk';

const mock = new MockLlmClient({
  responses: ['First canned answer', 'Second canned answer'],
});

const r1 = await mock.query('Hello');
console.log(r1.content);     // "First canned answer"
console.log(mock.callCount); // 1

// Custom generator
const mock2 = new MockLlmClient({
  responseGenerator: (prompt) => `Echo: ${prompt}`,
});
```

### Rate limiting

All LLM clients share a process-wide token-bucket rate limiter. It is enabled
by default and adapts automatically:

- On **HTTP 429** the budget is reduced by a configurable factor (default 0.7x).
- After a cooldown period and enough consecutive successes the budget recovers.
- Callers block in `acquire()` until tokens are available; a timeout prevents
  indefinite waits.

No application code is needed -- rate limiting is built into every `query` and
`streamQuery` call.

### Error hierarchy

All LLM errors extend `LlmError`:

| Class | Trigger |
|---|---|
| `LlmAuthenticationError` | Invalid / missing API key, billing errors |
| `LlmRateLimitError` | HTTP 429 from the provider |
| `LlmTimeoutError` | Request exceeded timeout |
| `LlmContextLengthError` | Prompt exceeds model context window |

```ts
import { LlmRateLimitError } from '@sw4rm/js-sdk';

try {
  await client.query('...');
} catch (err) {
  if (err instanceof LlmRateLimitError) {
    // The rate limiter already reduced its budget; retry after a delay
  }
}
```

### Environment variables

| Variable | Default | Description |
|---|---|---|
| `LLM_CLIENT_TYPE` | `mock` | Provider for the factory: `groq`, `anthropic`, or `mock` |
| `LLM_DEFAULT_MODEL` | per-provider | Override the default model for any provider |
| `GROQ_API_KEY` | -- | Groq API key |
| `GROQ_DEFAULT_MODEL` | `llama-3.3-70b-versatile` | Default model for the Groq client |
| `ANTHROPIC_API_KEY` | -- | Anthropic API key |
| `ANTHROPIC_DEFAULT_MODEL` | `claude-sonnet-4-20250514` | Default model for the Anthropic client |
| `LLM_RATE_LIMIT_ENABLED` | `1` | Set to `0` to disable the rate limiter |
| `LLM_RATE_LIMIT_TOKENS_PER_MIN` | `250000` | Token budget per minute |
| `LLM_RATE_LIMIT_ADAPTIVE` | `1` | Enable adaptive throttling on 429 |
| `LLM_RATE_LIMIT_REDUCTION_FACTOR` | `0.7` | Budget multiplier after a 429 |
| `LLM_RATE_LIMIT_RECOVERY_FACTOR` | `1.1` | Budget multiplier during recovery |
| `LLM_RATE_LIMIT_COOLDOWN_SECONDS` | `30` | Seconds to wait before recovery begins |
| `LLM_RATE_LIMIT_RECOVERY_SUCCESS_THRESHOLD` | `20` | Consecutive successes needed for recovery |

## Spec compliance

- Envelope, ACK lifecycle, Scheduler (priority/Duration), Worktree, HITL, Negotiation, Reasoning, Connector, Logging clients implemented.
- Streaming resilience and interceptor hooks included by default.
- JSON persistence for ActivityBuffer and ACK states.

## Operational Contracts

For production deployments, see the **[Operational Contracts](../docs/OPERATIONAL_CONTRACTS.md)** documentation, which defines:

- Connection timeouts and keep-alive settings
- Retry policies and error handling
- Data consistency guarantees
- Idempotency contracts
- State persistence guarantees

These are protocol-level contracts that all SW4RM SDKs honor.

## Links

- Top-level README (overview and API): `../../README.md`
- Quickstart for running local services: `../../QUICKSTART.md`
- Operational Contracts: `../docs/OPERATIONAL_CONTRACTS.md`
- Python SDK: `../py_sdk/README.md`
- Rust SDK: `../rust_sdk/README.md`
