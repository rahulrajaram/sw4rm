// Example: Reasoning checks
// import { ReasoningClient } from '@sw4rm/js-sdk';
import { ReasoningClient } from '../../sdks/js_sdk/src/index.ts';

async function main() {
  const r = new ReasoningClient({ address: 'localhost:50058' });
  const p = await r.checkParallelism('scope:A', 'scope:B');
  console.log('Parallelism:', p);
  const d = await r.evaluateDebate('neg-1', 'proposalA', 'proposalB', 'HIGH');
  console.log('Debate score:', d);
}

main().catch(e => { console.error(e); process.exit(1); });
