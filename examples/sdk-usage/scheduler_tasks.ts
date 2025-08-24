// Example: Scheduler submit → preempt → shutdown → poll/purge
// import { SchedulerClient } from '@sw4rm/js-sdk';
import { SchedulerClient } from '../../sdks/js_sdk/src/index.ts';

const SCHEDULER_ADDR = process.env.SW4RM_SCHEDULER_ADDR
  || `${process.env.SCHEDULER_HOST || 'localhost'}:${process.env.SCHEDULER_PORT || '50053'}`;

async function main() {
  const scheduler = new SchedulerClient({ address: SCHEDULER_ADDR });
  const agentId = 'agent-js-1';
  const taskId = 'task-123';

  const submit = await scheduler.submitTask({
    agent_id: agentId,
    task_id: taskId,
    priority: 0,
    params: new TextEncoder().encode(JSON.stringify({ work: 'do-thing' })),
    content_type: 'application/json',
    scope: 'repo:myrepo/path',
  });
  console.log('Submit:', submit);

  const preempt = await scheduler.requestPreemption(agentId, taskId, 'example-preempt');
  console.log('Preempt enqueued:', preempt);

  const poll = await scheduler.pollActivityBuffer(agentId);
  console.log('Activity entries:', poll.length);

  const purged = await scheduler.purgeActivity(agentId, [taskId]);
  console.log('Purged count:', purged);

  const shutdown = await scheduler.shutdownAgent(agentId, 1000);
  console.log('Shutdown ok:', shutdown.ok);
}

main().catch(e => { console.error(e); process.exit(1); });
