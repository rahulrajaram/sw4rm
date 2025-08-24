// Example: Router streaming + sendMessageWithAck
// import { RouterClient, ACKLifecycleManager, createResilientIncomingStream, buildEnvelope, MessageType, sendMessageWithAck } from '@sw4rm/js-sdk';
import { RouterClient, ACKLifecycleManager, createResilientIncomingStream, buildEnvelope, MessageType, sendMessageWithAck, AckStage } from '../../sdks/js_sdk/src/index.ts';

const ROUTER_ADDR = process.env.SW4RM_ROUTER_ADDR
  || `${process.env.ROUTER_HOST || 'localhost'}:${process.env.ROUTER_PORT || '50051'}`;

async function main() {
  const agentId = 'agent-js-1';
  const router = new RouterClient({ address: ROUTER_ADDR });
  const inbound = createResilientIncomingStream(router, agentId);
  const acks = new ACKLifecycleManager();

  // Extract ACK from payload when router forwards ACK envelopes
  const extractor = (item: any) => {
    const msg = item?.msg;
    if (!msg) return undefined;
    const mt = msg.message_type;
    const isAck = (mt === MessageType.ACKNOWLEDGEMENT) || (mt === 'ACKNOWLEDGEMENT') || (mt === 5);
    if (isAck && msg.payload && typeof msg.content_type === 'string') {
      try {
        const s = new TextDecoder().decode(msg.payload);
        const j = JSON.parse(s);
        if (j && j.ack_for_message_id) {
          return { ackFor: j.ack_for_message_id as string, stage: (j.ack_stage ?? AckStage.RECEIVED) as AckStage };
        }
      } catch {}
    }
    // Legacy fallback (non-proto mock path)
    if (msg.ack_for_message_id) {
      return { ackFor: msg.ack_for_message_id as string, stage: (msg.ack_stage ?? AckStage.RECEIVED) as AckStage };
    }
    return undefined;
  };

  const env = buildEnvelope({
    producer_id: agentId,
    message_type: MessageType.DATA,
    content_type: 'application/json',
    payload: new TextEncoder().encode(JSON.stringify({ hello: 'world' })),
  });

  await sendMessageWithAck(router, inbound as any, env, acks, extractor, { receivedTimeoutMs: 10000 });
  console.log('ACK state:', acks.get(env.message_id));
  // Stop the inbound stream to allow process exit
  (inbound as any).stop?.();
}

main().catch(e => { console.error(e); process.exit(1); });
