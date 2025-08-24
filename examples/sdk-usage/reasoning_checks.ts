// Example: Reasoning checks
// import { ReasoningClient } from '@sw4rm/js-sdk';
import { ReasoningClient } from '../../sdks/js_sdk/src/index.ts';

const REASONING_ADDR = process.env.SW4RM_REASONING_ADDR
  || `${process.env.REASONING_HOST || 'localhost'}:${process.env.REASONING_PORT || '50058'}`;

async function main() {
  const r = new ReasoningClient({ address: REASONING_ADDR });
  const p = await r.checkParallelism('scope:A', 'scope:B');
  console.log('Parallelism:', p);
  const d = await r.evaluateDebate('neg-1', 'proposalA', 'proposalB', 'HIGH');
  console.log('Debate score:', d);
}

main().catch(e => { console.error(e); process.exit(1); });
