import { describe, it, expect } from 'vitest';
import { ActivityBuffer } from '../src/internal/runtime/activityBuffer.js';
import { ACKLifecycleManager, AckStage } from '../src/internal/runtime/ackLifecycle.js';
import { JSONFilePersistence } from '../src/persistence/persistence.js';
import { RuntimePersistence } from '../src/runtime/persistenceAdapter.js';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

describe('JSON persistence', () => {
  it('saves and loads runtime state', async () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'sw4rm-js-'));
    const buf = new ActivityBuffer();
    buf.upsert({ task_id: 't1', repo_id: 'r', worktree_id: 'w', branch: 'b', description: 'd', timestamp: new Date().toISOString() });
    const ack = new ACKLifecycleManager();
    ack.mark('m1', AckStage.RECEIVED);
    const rp = RuntimePersistence.json(dir, buf, ack);
    await rp.save();

    const buf2 = new ActivityBuffer();
    const ack2 = new ACKLifecycleManager();
    const rp2 = RuntimePersistence.json(dir, buf2, ack2);
    await rp2.load();
    expect(buf2.list().length).toBe(1);
    expect(ack2.get('m1')?.stage).toBe(AckStage.RECEIVED);
  });
});

