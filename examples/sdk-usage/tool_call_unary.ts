// Example: Tool unary call
// import { ToolClient } from '@sw4rm/js-sdk';
import { ToolClient } from '../../sdks/js_sdk/src';

const TOOL_ADDR = process.env.SW4RM_TOOL_ADDR
  || `${process.env.TOOL_HOST || 'localhost'}:${process.env.TOOL_PORT || '50054'}`;

async function main() {
  const tool = new ToolClient({ address: TOOL_ADDR });
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
