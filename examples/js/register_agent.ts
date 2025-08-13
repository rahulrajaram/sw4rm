// Example: Registry register → heartbeat → deregister
// import { RegistryClient } from '@sw4rm/js-sdk';
import { RegistryClient } from '../../sdks/js_sdk/src/index.ts';

async function main() {
  const registry = new RegistryClient({ address: 'localhost:50051' });
  const agent = {
    agent_id: 'agent-js-1',
    name: 'JS Agent',
    description: 'Example JS agent',
    capabilities: ['routing','tools'],
    communication_class: 'STANDARD',
    modalities_supported: ['application/json','text/plain'],
    reasoning_connectors: [],
  };
  const reg = await registry.registerAgent(agent);
  console.log('Registered:', reg);
  const hb = await registry.heartbeat(agent.agent_id, 'RUNNABLE', { alive: 'true' });
  console.log('Heartbeat ok:', hb);
  const bye = await registry.deregisterAgent(agent.agent_id, 'example finished');
  console.log('Deregistered:', bye);
}

main().catch(e => { console.error(e); process.exit(1); });
