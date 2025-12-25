#!/usr/bin/env tsx

// Minimal ACK agent: subscribes to Router stream and sends ACK messages
// back for any DATA message it sees. Run alongside another client to
// demonstrate sendMessageWithAck end-to-end.

import { fileURLToPath } from 'node:url';
import path from 'node:path';
import {
  RegistryClient,
  RouterClient,
  buildEnvelope,
  MessageType,
  AckStage,
  createResilientIncomingStream,
} from '../../../../sdks/js_sdk/src/index.ts';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const REGISTRY_ADDR = process.env.SW4RM_REGISTRY_ADDR
  || `${process.env.REGISTRY_HOST || 'localhost'}:${process.env.REGISTRY_PORT || '50052'}`;
const ROUTER_ADDR = process.env.SW4RM_ROUTER_ADDR
  || `${process.env.ROUTER_HOST || 'localhost'}:${process.env.ROUTER_PORT || '50051'}`;

const AGENT_ID = process.env.AGENT_ID || 'ack-agent-1';

async function main() {
  const registry = new RegistryClient({ address: REGISTRY_ADDR });
  const router = new RouterClient({ address: ROUTER_ADDR });

  // Best-effort register (optional for routing, good for visibility)
  try {
    await registry.registerAgent({
      agent_id: AGENT_ID,
      name: 'AckAgent',
      description: 'Emits ACKs for DATA messages',
      capabilities: ['ack'],
      communication_class: 'STANDARD',
      modalities_supported: ['application/json'],
      reasoning_connectors: [],
    } as any);
    console.log(`[ack] registered as ${AGENT_ID} at ${REGISTRY_ADDR}`);
  } catch (e) {
    console.warn('[ack] register failed (continuing):', e);
  }

  const stream = createResilientIncomingStream(router, AGENT_ID);
  console.log(`[ack] streaming (resilient) from router at ${ROUTER_ADDR} as ${AGENT_ID}`);

  stream.on('data', async (item: any) => {
    const msg = item?.msg || {};
    const mt = msg.message_type;
    const mid = msg.message_id;
    try { console.log(`[ack] recv mt=${mt} id=${mid}`); } catch {}
    const isData = (mt === MessageType.DATA) || (mt === 'DATA') || (mt === 2);
    if (isData) {
      const targetId = msg.message_id;
      // Send ACK with JSON payload so clients can extract reliably
      const ackPayload = new TextEncoder().encode(
        JSON.stringify({ ack_for_message_id: targetId, ack_stage: AckStage.RECEIVED })
      );
      const ack = buildEnvelope({
        producer_id: AGENT_ID,
        message_type: MessageType.ACKNOWLEDGEMENT,
        content_type: 'application/vnd.sw4rm.ack+json;v=1',
        payload: ackPayload,
        correlation_id: msg.correlation_id || undefined,
      });
      try {
        await router.sendMessage(ack);
        console.log(`[ack] sent ACK for ${targetId}`);
      } catch (e) {
        console.warn('[ack] failed to send ACK:', e);
      }
    }
  });

  (stream as any).on('error', (e: any) => {
    console.error('[ack] stream error:', e);
    process.exit(1);
  });

  (stream as any).on('end', () => {
    console.log('[ack] stream ended');
    process.exit(0);
  });
}

main().catch((e) => { console.error(e); process.exit(1); });
