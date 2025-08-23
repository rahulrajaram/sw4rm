// Example: End-to-end smoke (register → route/ACK → schedule → tool → log)
// import { RegistryClient, RouterClient, SchedulerClient, ToolClient, LoggingClient, buildEnvelope, MessageType, ACKLifecycleManager, createResilientIncomingStream, sendMessageWithAck } from '@sw4rm/js-sdk';
import { RegistryClient, RouterClient, SchedulerClient, ToolClient, LoggingClient, buildEnvelope, MessageType, ACKLifecycleManager, createResilientIncomingStream, sendMessageWithAck } from '../../sdks/js_sdk/src/index.ts';

const REGISTRY_ADDR = process.env.SW4RM_REGISTRY_ADDR
  || `${process.env.REGISTRY_HOST || 'localhost'}:${process.env.REGISTRY_PORT || '50052'}`;
const ROUTER_ADDR = process.env.SW4RM_ROUTER_ADDR
  || `${process.env.ROUTER_HOST || 'localhost'}:${process.env.ROUTER_PORT || '50051'}`;
const SCHEDULER_ADDR = process.env.SW4RM_SCHEDULER_ADDR
  || `${process.env.SCHEDULER_HOST || 'localhost'}:${process.env.SCHEDULER_PORT || '50053'}`;
const TOOL_ADDR = process.env.SW4RM_TOOL_ADDR
  || `${process.env.TOOL_HOST || 'localhost'}:${process.env.TOOL_PORT || '50054'}`;
const LOGGING_ADDR = process.env.SW4RM_LOGGING_ADDR
  || `${process.env.LOGGING_HOST || 'localhost'}:${process.env.LOGGING_PORT || '50059'}`;

async function main() {
  const agentId = 'agent-js-1';
  const registry = new RegistryClient({ address: REGISTRY_ADDR });
  const router = new RouterClient({ address: ROUTER_ADDR });
  const scheduler = new SchedulerClient({ address: SCHEDULER_ADDR });
  const tool = new ToolClient({ address: TOOL_ADDR });
  const log = new LoggingClient({ address: LOGGING_ADDR });

  await registry.registerAgent({ agent_id: agentId, name: 'JS Agent', description: 'E2E example', capabilities: [], communication_class: 'STANDARD', modalities_supported: [], reasoning_connectors: [] });

  const inbound = createResilientIncomingStream(router, agentId);
  const acks = new ACKLifecycleManager();
  const env = buildEnvelope({ producer_id: agentId, message_type: MessageType.DATA, content_type: 'application/json', payload: new TextEncoder().encode('{"ping":true}') });
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
          return { ackFor: j.ack_for_message_id as string, stage: (j.ack_stage ?? 1) as number };
        }
      } catch {}
    }
    if (msg.ack_for_message_id) {
      return { ackFor: msg.ack_for_message_id as string, stage: (msg.ack_stage ?? 1) as number };
    }
    return undefined;
  };
  await sendMessageWithAck(router, inbound as any, env, acks, extractor, { receivedTimeoutMs: 10000 });
  (inbound as any).stop?.();

  await scheduler.submitTask({ agent_id: agentId, task_id: 't1', priority: 0, params: new Uint8Array(), content_type: 'application/octet-stream', scope: 'repo:x' });

  await tool.call({ call_id: 'c1', tool_name: 'echo', content_type: 'application/json', args: new TextEncoder().encode('{"x":1}') });

  const now = new Date();
  await log.ingest({ ts: { seconds: Math.floor(now.getTime()/1000), nanos: (now.getTime()%1000)*1e6 }, correlation_id: env.correlation_id, agent_id: agentId, event_type: 'END_TO_END', level: 'INFO', details_json: '{}' });

  await registry.deregisterAgent(agentId, 'done');
  console.log('End-to-end example completed');
}

main().catch(e => { console.error(e); process.exit(1); });
