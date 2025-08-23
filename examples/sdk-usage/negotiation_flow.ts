// Example: Negotiation open → propose/counter → evaluate → decide
// import { NegotiationClient } from '@sw4rm/js-sdk';
import { NegotiationClient } from '../../sdks/js_sdk/src/index.ts';

const NEGOTIATION_ADDR = process.env.SW4RM_NEGOTIATION_ADDR
  || `${process.env.NEGOTIATION_HOST || 'localhost'}:${process.env.NEGOTIATION_PORT || '50057'}`;

async function main() {
  const n = new NegotiationClient({ address: NEGOTIATION_ADDR });
  const negotiation_id = 'neg-1';
  await n.open({ negotiation_id, correlation_id: 'corr-1', topic: '/api/orders', participants: ['A','B'], intensity: 'MEDIUM' });
  await n.propose({ negotiation_id, from_agent: 'A', content_type: 'application/json', payload: new TextEncoder().encode('{}') });
  await n.counter({ negotiation_id, from_agent: 'B', content_type: 'application/json', payload: new TextEncoder().encode('{}') });
  await n.evaluate({ negotiation_id, from_agent: 'A', confidence_score: 0.7, notes: 'ok' });
  await n.decide({ negotiation_id, decided_by: 'consensus', content_type: 'application/json', result: new TextEncoder().encode('{}') });
  console.log('Negotiation concluded');
}

main().catch(e => { console.error(e); process.exit(1); });
