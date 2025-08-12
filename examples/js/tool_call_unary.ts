// Example: Tool unary call
// import { ToolClient } from '@sw4rm/js-sdk';
import { ToolClient } from '../../sdks/js_sdk/src/index.ts';

async function main() {
  const tool = new ToolClient({ address: 'localhost:50054' });
  const frame = await tool.call({
    call_id: 'call-1',
    tool_name: 'echo',
    content_type: 'application/json',
    args: new TextEncoder().encode(JSON.stringify({ msg: 'hello' })),
    policy: { worktree_required: false },
  });
  console.log('Tool result:', new TextDecoder().decode(frame.data));
}

main().catch(e => { console.error(e); process.exit(1); });
