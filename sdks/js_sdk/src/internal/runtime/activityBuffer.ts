// Advisory ActivityBuffer per spec §10

export interface ActivityRecord {
  task_id: string;
  repo_id: string;
  worktree_id: string;
  branch: string;
  description: string; // ≤200 words
  timestamp: string; // ISO-8601
}

export interface BufferStrategy {
  prune(records: ActivityRecord[], maxEntries: number): ActivityRecord[];
}

export class MaxEntriesStrategy implements BufferStrategy {
  prune(records: ActivityRecord[], maxEntries: number): ActivityRecord[] {
    if (records.length <= maxEntries) return records;
    const overflow = records.length - maxEntries;
    return records.slice(overflow); // drop oldest
  }
}

export class ActivityBuffer {
  private records = new Map<string, ActivityRecord>();
  private maxEntries: number;
  private strategy: BufferStrategy;

  constructor(opts?: { maxEntries?: number; strategy?: BufferStrategy }) {
    this.maxEntries = opts?.maxEntries ?? 1000;
    this.strategy = opts?.strategy ?? new MaxEntriesStrategy();
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

  private prune() {
    const arr = this.list();
    const pruned = this.strategy.prune(arr, this.maxEntries);
    if (pruned.length === arr.length) return;
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
