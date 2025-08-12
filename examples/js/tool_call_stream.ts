// Example: Tool streaming call
// import { ToolClient } from '@sw4rm/js-sdk';
import { ToolClient } from '../../sdks/js_sdk/src/index.ts';

async function main() {
  const tool = new ToolClient({ address: 'localhost:50054' });
  const stream = tool.callStream({
    call_id: 'call-2',
    tool_name: 'long_task',
    content_type: 'application/json',
    args: new TextEncoder().encode(JSON.stringify({ duration_ms: 1000 })),
    policy: { worktree_required: false },
    stream: true,
  });
  stream.on('data', (frame: any) => {
    console.log('Frame', frame.frame_no, frame.final);
  });
  await new Promise<void>((resolve, reject) => {
    stream.on('end', () => resolve());
    stream.on('error', reject);
  });
}

main().catch(e => { console.error(e); process.exit(1); });
