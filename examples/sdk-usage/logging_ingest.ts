// Example: Logging ingest
// import { LoggingClient } from '@sw4rm/js-sdk';
import { LoggingClient } from '../../sdks/js_sdk/src/index.ts';

const LOGGING_ADDR = process.env.SW4RM_LOGGING_ADDR
  || `${process.env.LOGGING_HOST || 'localhost'}:${process.env.LOGGING_PORT || '50059'}`;

async function main() {
  const log = new LoggingClient({ address: LOGGING_ADDR });
  const now = new Date();
  const ok = await log.ingest({
    ts: { seconds: Math.floor(now.getTime()/1000), nanos: (now.getTime()%1000)*1e6 },
    correlation_id: 'corr-1',
    agent_id: 'agent-js-1',
    event_type: 'EXAMPLE_EVENT',
    level: 'INFO',
    details_json: JSON.stringify({ example: true }),
  });
  console.log('Ingest ok:', ok);
}

main().catch(e => { console.error(e); process.exit(1); });
