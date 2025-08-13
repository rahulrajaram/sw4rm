import { ActivityBuffer } from '../internal/runtime/activityBuffer.js';
import { ACKLifecycleManager } from '../internal/runtime/ackLifecycle.js';
import { JSONFilePersistence, PersistenceBackend } from '../persistence/persistence.js';

export interface PersistenceOptions {
  autosaveMs?: number; // if provided, periodically save
}

export class RuntimePersistence {
  private timer?: NodeJS.Timeout;
  constructor(
    private backend: PersistenceBackend,
    private activity: ActivityBuffer,
    private acks: ACKLifecycleManager,
    private opts?: PersistenceOptions,
  ) {}

  static json(baseDir: string, activity: ActivityBuffer, acks: ACKLifecycleManager, opts?: PersistenceOptions) {
    return new RuntimePersistence(new JSONFilePersistence(baseDir), activity, acks, opts);
  }

  async load() {
    const [a, k] = await Promise.all([this.backend.loadActivity(), this.backend.loadAcks()]);
    this.activity.fromJSON(a as any);
    this.acks.fromJSON(k as any);
  }

  async save() {
    await Promise.all([
      this.backend.saveActivity(this.activity.toJSON()),
      this.backend.saveAcks(this.acks.toJSON()),
    ]);
  }

  startAutosave() {
    if (!this.opts?.autosaveMs) return;
    if (this.timer) clearInterval(this.timer);
    this.timer = setInterval(() => void this.save().catch(() => {}), this.opts.autosaveMs);
  }

  stopAutosave() {
    if (this.timer) clearInterval(this.timer);
    this.timer = undefined;
  }
}

