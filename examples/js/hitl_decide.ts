// Example: HITL decide
// import { HITLClient } from '@sw4rm/js-sdk';
import { HITLClient } from '../../sdks/js_sdk/src/index.ts';

async function main() {
  const hitl = new HITLClient({ address: 'localhost:50056' });
  const inv = {
    reason_type: 'SECURITY_APPROVAL',
    context: new TextEncoder().encode(JSON.stringify({ action: 'publish' })),
    proposed_actions: ['approve','reject'],
    priority: 0,
  };
  const decision = await hitl.decide(inv);
  console.log('Decision:', decision);
}

main().catch(e => { console.error(e); process.exit(1); });
