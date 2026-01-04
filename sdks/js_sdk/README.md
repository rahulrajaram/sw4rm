# SW4RM JavaScript SDK

Reference JavaScript SDK for the SW4RM Agentic Protocol. This is one of three SDKs in this repository (Python, Rust, JavaScript). 🚧 Under development: initial implementation includes a basic RegistryClient and core utilities.

## Install

```bash
npm install @sw4rm/js-sdk
```

## Quick Start with Working Services

🎉 **NEW**: Complete working example with services included! You can now run a full SW4RM setup locally.

### 1. Start the Services

```bash
cd ../../examples/reference-services/
./start_services_local.sh
```

### 2. Test the Setup

```bash
# Test the complete setup
python test_complete_setup.py
```

### 3. Run JavaScript Examples

```bash
cd ../../examples/sdk-usage/
npm install
npm run register_agent    # Register an agent
npm run router_send_receive  # Send and receive messages
```

You should see successful agent registration and message routing!

## Quick Start

```typescript
import { RegistryClient, AgentState, CommunicationClass } from '@sw4rm/js-sdk';

const client = new RegistryClient('localhost:50051');

// Register agent
await client.registerAgent({
  agent_id: 'my-agent',
  name: 'My Agent',
  description: 'Example agent implementation',
  capabilities: ['example'],
  communication_class: CommunicationClass.STANDARD,
  modalities_supported: ['application/json'],
  reasoning_connectors: ['http://localhost:8080'],
});

// Send heartbeat
await client.heartbeat('my-agent', AgentState.RUNNING);

// Deregister
await client.deregisterAgent('my-agent', 'Done');
```

## Implementation Status

- ✅ Base gRPC client infrastructure
- ✅ RegistryClient (agent registration, heartbeat, deregistration)
- ✅ TypeScript type definitions
- ✅ Unit tests
- ⏳ Additional service clients (planned)

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
