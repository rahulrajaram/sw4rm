import { ActivityBuffer, ActivityRecord } from '../internal/runtime/activityBuffer.js';
import { SchedulerClient } from '../clients/scheduler.js';

export class ActivityBufferSync {
  constructor(private buf: ActivityBuffer, private sched: SchedulerClient) {}

  async refresh(agentId: string) {
    const entries = await this.sched.pollActivityBuffer(agentId);
    for (const e of entries) {
      const rec: ActivityRecord = {
        task_id: e.task_id,
        repo_id: e.repo_id,
        worktree_id: e.worktree_id,
        branch: e.branch,
        description: e.description,
        timestamp: e.timestamp,
      };
      this.buf.upsert(rec);
    }
  }

  async purge(agentId: string, taskIds: string[]) {
    if (!taskIds.length) return 0;
    const purged = await this.sched.purgeActivity(agentId, taskIds);
    for (const id of taskIds) this.buf.remove(id);
    return purged;
  }
}

