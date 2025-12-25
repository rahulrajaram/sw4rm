#!/usr/bin/env npx tsx
/**
 * Minimal echo agent example using SW4RM Agentic Protocol (JavaScript SDK).
 *
 * This example demonstrates:
 * - Agent registration with RegistryClient
 * - Message receiving via streaming
 * - Echoing DATA messages back to the router
 * - Basic ACK lifecycle (RECEIVED stage)
 * - Graceful deregistration on shutdown
 *
 * Prerequisites:
 *   - Install dependencies: `npm install`
 *   - Build the SDK: `npm run build`
 *   - SW4RM services running on default ports
 *
 * Run:
 *   npx tsx examples/echoAgent.ts --agent-id echo-1 --name EchoAgent
 *
 * Environment Variables:
 *   SW4RM_ROUTER_ADDR   - Router service address (default: localhost:50051)
 *   SW4RM_REGISTRY_ADDR - Registry service address (default: localhost:50052)
 *   AGENT_ID            - Agent identifier (default: echo-1)
 *   AGENT_NAME          - Agent display name (default: EchoAgent)
 *
 * @packageDocumentation
 */

import { parseArgs } from 'node:util';
import {
  RegistryClient,
  RouterClient,
  buildEnvelope,
  MessageType,
  AckStage,
  ACKLifecycleManager,
} from '../src/index.js';
import type { AgentDescriptor } from '../src/clients/registry.js';
import type { EnvelopeBuilt } from '../src/internal/envelope.js';

// Default addresses matching SW4RM protocol conventions
const DEFAULT_ROUTER_ADDR = 'localhost:50051';
const DEFAULT_REGISTRY_ADDR = 'localhost:50052';

interface CliArgs {
  agentId: string;
  name: string;
  routerAddr: string;
  registryAddr: string;
}

/**
 * Parse command line arguments and environment variables.
 */
function parseCliArgs(): CliArgs {
  const { values } = parseArgs({
    options: {
      'agent-id': { type: 'string', default: process.env.AGENT_ID ?? 'echo-1' },
      name: { type: 'string', default: process.env.AGENT_NAME ?? 'EchoAgent' },
      router: { type: 'string', default: process.env.SW4RM_ROUTER_ADDR ?? DEFAULT_ROUTER_ADDR },
      registry: { type: 'string', default: process.env.SW4RM_REGISTRY_ADDR ?? DEFAULT_REGISTRY_ADDR },
    },
  });

  return {
    agentId: values['agent-id'] as string,
    name: values.name as string,
    routerAddr: values.router as string,
    registryAddr: values.registry as string,
  };
}

/**
 * Main echo agent implementation.
 *
 * Registers with the SW4RM registry, listens for incoming messages,
 * and echoes DATA messages back to the router with basic ACK tracking.
 */
async function main(): Promise<number> {
  const args = parseCliArgs();

  console.log(`[EchoAgent] Starting with ID: ${args.agentId}`);
  console.log(`[EchoAgent] Router: ${args.routerAddr}, Registry: ${args.registryAddr}`);

  // Initialize clients
  const registry = new RegistryClient({ address: args.registryAddr });
  const router = new RouterClient({ address: args.routerAddr });

  // Initialize ACK lifecycle manager for tracking message states
  const ackManager = new ACKLifecycleManager();

  // Agent descriptor for registration
  const descriptor: AgentDescriptor = {
    agent_id: args.agentId,
    name: args.name,
    description: 'Echoes incoming DATA messages back to the router.',
    capabilities: ['echo'],
    communication_class: 'STANDARD', // CommunicationClass enum as string
    modalities_supported: ['text/plain', 'application/json'],
    reasoning_connectors: [],
  };

  // Register the agent
  try {
    const regResult = await registry.registerAgent(descriptor);
    console.log(`[Register] accepted=${regResult.accepted} reason=${regResult.reason ?? 'none'}`);
    if (!regResult.accepted) {
      console.error('[Register] Registration rejected, exiting');
      return 1;
    }
  } catch (err) {
    console.error('[Register] Failed to register agent:', err);
    return 1;
  }

  // Track shutdown state
  let stopRequested = false;

  // Handle graceful shutdown
  const shutdown = async () => {
    if (stopRequested) return;
    stopRequested = true;
    console.log('\n[Shutdown] Received shutdown signal...');

    try {
      const deregResult = await registry.deregisterAgent(args.agentId, 'shutdown');
      console.log(`[Shutdown] Deregistered: ${deregResult}`);
    } catch (err) {
      console.error('[Shutdown] Deregistration failed:', err);
    }

    process.exit(0);
  };

  process.on('SIGINT', shutdown);
  process.on('SIGTERM', shutdown);

  // Start streaming incoming messages
  console.log(`[Stream] Starting message stream for agent ${args.agentId}...`);

  try {
    const stream = router.streamIncoming(args.agentId);

    stream.on('data', async (item: { msg: EnvelopeBuilt }) => {
      if (stopRequested) return;

      const msg = item.msg;
      const messageId = msg.message_id;
      const messageType = msg.message_type;
      const payloadLen = msg.payload?.length ?? 0;

      console.log(`[Recv] type=${messageType} len=${payloadLen} id=${messageId}`);

      // Mark message as received in ACK lifecycle
      ackManager.mark(messageId, AckStage.RECEIVED);

      // Echo back DATA messages (type 2)
      if (messageType === MessageType.DATA || messageType === 2) {
        const echoEnvelope = buildEnvelope({
          producer_id: args.agentId,
          message_type: MessageType.DATA,
          content_type: msg.content_type || 'application/octet-stream',
          payload: msg.payload,
          correlation_id: msg.correlation_id, // Preserve correlation for tracing
        });

        try {
          const sendResult = await router.sendMessage(echoEnvelope);
          console.log(`[Echo] accepted=${sendResult.accepted} reason=${sendResult.reason ?? 'none'}`);

          // Mark original message as fulfilled after successful echo
          ackManager.mark(messageId, AckStage.FULFILLED, 'echo_sent');
        } catch (err) {
          console.error('[Echo] Send failed:', err);
          ackManager.mark(messageId, AckStage.FAILED, 'echo_send_failed');
        }
      } else {
        // Non-DATA messages are acknowledged but not echoed
        ackManager.mark(messageId, AckStage.READ, 'non_data_message');
      }
    });

    stream.on('error', (err: Error) => {
      console.error('[Stream] Error:', err.message);
      if (!stopRequested) {
        console.log('[Stream] Attempting reconnection in 5 seconds...');
        setTimeout(() => {
          if (!stopRequested) {
            main(); // Simple restart logic
          }
        }, 5000);
      }
    });

    stream.on('end', () => {
      console.log('[Stream] Stream ended');
      if (!stopRequested) {
        shutdown();
      }
    });

    // Keep the process running
    await new Promise(() => {}); // Never resolves - waits for signal

  } catch (err) {
    console.error('[Stream] Failed to start stream:', err);
    await shutdown();
    return 1;
  }

  return 0;
}

// Entry point
main().catch((err) => {
  console.error('[Fatal] Unhandled error:', err);
  process.exit(1);
});
