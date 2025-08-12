// Example: Router streaming + sendMessageWithAck
// import { RouterClient, ACKLifecycleManager, createResilientIncomingStream, buildEnvelope, MessageType, sendMessageWithAck } from '@sw4rm/js-sdk';
import { RouterClient, ACKLifecycleManager, createResilientIncomingStream, buildEnvelope, MessageType, sendMessageWithAck } from '../../sdks/js_sdk/src/index.ts';

async function main() {
  const agentId = 'agent-js-1';
  const router = new RouterClient({ address: 'localhost:50052' });
  const inbound = createResilientIncomingStream(router, agentId);
  const acks = new ACKLifecycleManager();

  // Simple ACK extractor if ACKs are sent as envelopes with JSON payload
  const extractor = (item: any) => ({ ackFor: item.msg?.ack_for_message_id, stage: item.msg?.ack_stage });

  const env = buildEnvelope({
    producer_id: agentId,
    message_type: MessageType.DATA,
    content_type: 'application/json',
    payload: new TextEncoder().encode(JSON.stringify({ hello: 'world' })),
  });

  await sendMessageWithAck(router, inbound as any, env, acks, extractor, { receivedTimeoutMs: 10000 });
  console.log('ACK state:', acks.get(env.message_id));
}

main().catch(e => { console.error(e); process.exit(1); });
