// Example: Worktree bind → request switch → approve → status
// import { WorktreeClient } from '@sw4rm/js-sdk';
import { WorktreeClient } from '../../sdks/js_sdk/src/index.ts';

async function main() {
  const worktree = new WorktreeClient({ address: 'localhost:50055' });
  const agentId = 'agent-js-1';
  const bind = await worktree.bind(agentId, 'repo-1', 'home');
  console.log('Bind ok:', bind);
  const req = await worktree.requestSwitch(agentId, 'feature-x', true);
  console.log('Switch requested, state:', req.state);
  const approve = await worktree.approveSwitch(agentId, 'feature-x', 60000);
  console.log('Approved, state:', approve);
  const st = await worktree.status(agentId);
  console.log('Status:', st);
}

main().catch(e => { console.error(e); process.exit(1); });
