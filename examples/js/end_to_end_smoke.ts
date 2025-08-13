// Example: End-to-end smoke (register → route/ACK → schedule → tool → log)
// import { RegistryClient, RouterClient, SchedulerClient, ToolClient, LoggingClient, buildEnvelope, MessageType, ACKLifecycleManager, createResilientIncomingStream, sendMessageWithAck } from '@sw4rm/js-sdk';
import { RegistryClient, RouterClient, SchedulerClient, ToolClient, LoggingClient, buildEnvelope, MessageType, ACKLifecycleManager, createResilientIncomingStream, sendMessageWithAck } from '../../sdks/js_sdk/src/index.ts';

async function main() {
  const agentId = 'agent-js-1';
  const registry = new RegistryClient({ address: 'localhost:50051' });
  const router = new RouterClient({ address: 'localhost:50052' });
  const scheduler = new SchedulerClient({ address: 'localhost:50053' });
  const tool = new ToolClient({ address: 'localhost:50054' });
  const log = new LoggingClient({ address: 'localhost:50059' });

  await registry.registerAgent({ agent_id: agentId, name: 'JS Agent', description: 'E2E example', capabilities: [], communication_class: 'STANDARD', modalities_supported: [], reasoning_connectors: [] });

  const inbound = createResilientIncomingStream(router, agentId);
  const acks = new ACKLifecycleManager();
  const env = buildEnvelope({ producer_id: agentId, message_type: MessageType.DATA, content_type: 'application/json', payload: new TextEncoder().encode('{"ping":true}') });
  const extractor = (item: any) => ({ ackFor: item.msg?.ack_for_message_id, stage: item.msg?.ack_stage });
  await sendMessageWithAck(router, inbound as any, env, acks, extractor);

  await scheduler.submitTask({ agent_id: agentId, task_id: 't1', priority: 0, params: new Uint8Array(), content_type: 'application/octet-stream', scope: 'repo:x' });

  await tool.call({ call_id: 'c1', tool_name: 'echo', content_type: 'application/json', args: new TextEncoder().encode('{"x":1}') });

  const now = new Date();
  await log.ingest({ ts: { seconds: Math.floor(now.getTime()/1000), nanos: (now.getTime()%1000)*1e6 }, correlation_id: env.correlation_id, agent_id: agentId, event_type: 'END_TO_END', level: 'INFO', details_json: '{}' });

  await registry.deregisterAgent(agentId, 'done');
  console.log('End-to-end example completed');
}

main().catch(e => { console.error(e); process.exit(1); });
