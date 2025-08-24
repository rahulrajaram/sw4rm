// Example: Persistence autosave for ActivityBuffer and ACKLifecycle
// import { ActivityBuffer, ACKLifecycleManager, RuntimePersistence } from '@sw4rm/js-sdk';
import { ActivityBuffer, ACKLifecycleManager, RuntimePersistence } from '../../sdks/js_sdk/src/index.ts';

async function main() {
  const buf = new ActivityBuffer();
  const acks = new ACKLifecycleManager();
  const persist = RuntimePersistence.json('.sw4rm', buf, acks, { autosaveMs: 5000 });
  await persist.load();
  persist.startAutosave();
  console.log('Autosave started. Press Ctrl+C to exit.');
}

main().catch(e => { console.error(e); process.exit(1); });
