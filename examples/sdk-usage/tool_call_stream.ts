// Example: Tool streaming call
// import { ToolClient } from '@sw4rm/js-sdk';
import { ToolClient } from '../../sdks/js_sdk/src';

const TOOL_ADDR = process.env.SW4RM_TOOL_ADDR
  || `${process.env.TOOL_HOST || 'localhost'}:${process.env.TOOL_PORT || '50054'}`;

async function main() {
  const tool = new ToolClient({ address: TOOL_ADDR });
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
