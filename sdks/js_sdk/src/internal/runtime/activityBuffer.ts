// Advisory ActivityBuffer per spec §10.
//
// This tracks per-task activity records (task_id/repo/worktree/branch/…)
// synced from PollActivityBuffer and persisted for the runtime.  There is no
// pluggable eviction API: per spec §10.1, capacity is enforced by rejecting
// at the service (error_code=activity_buffer_full) and the advisory history
// cap here applies a hardcoded count-based drop-oldest policy, which §10.1
// explicitly sanctions for completed/failed history entries.

export interface ActivityRecord {
  task_id: string;
  repo_id: string;
  worktree_id: string;
  branch: string;
  description: string; // ≤200 words
  timestamp: string; // ISO-8601
}

export class ActivityBuffer {
  private records = new Map<string, ActivityRecord>();
  private maxEntries: number;

  constructor(opts?: { maxEntries?: number }) {
    this.maxEntries = opts?.maxEntries ?? 1000;
  }

  upsert(rec: ActivityRecord) {
    this.records.set(rec.task_id, rec);
    this.prune();
  }

  remove(taskId: string) {
    this.records.delete(taskId);
  }

  list(): ActivityRecord[] {
    return [...this.records.values()].sort((a, b) => a.timestamp.localeCompare(b.timestamp));
  }

  recent(limit = 50): ActivityRecord[] {
    const arr = this.list();
    return arr.slice(Math.max(0, arr.length - limit));
  }

  reconcile(knownTaskIds: Set<string>) {
    for (const id of this.records.keys()) {
      if (!knownTaskIds.has(id)) this.records.delete(id);
    }
  }

  // Count-based cap for the advisory history window: drop the oldest records
  // beyond maxEntries (§10.1 history-entry eviction SHOULD).
  private prune() {
    const arr = this.list();
    if (arr.length <= this.maxEntries) return;
    const overflow = arr.length - this.maxEntries;
    const pruned = arr.slice(overflow);
    this.records.clear();
    for (const r of pruned) this.records.set(r.task_id, r);
  }

  toJSON(): ActivityRecord[] {
    return this.list();
  }

  fromJSON(records: ActivityRecord[]) {
    this.records.clear();
    for (const r of records) this.records.set(r.task_id, r);
    this.prune();
  }
}
