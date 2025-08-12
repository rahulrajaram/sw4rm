import { describe, it, expect } from 'vitest';
import { EventEmitter } from 'node:events';
import { buildEnvelope, MessageType } from '../src/internal/envelope.js';
import { sendMessageWithAck } from '../src/runtime/ackHelpers.js';
import { ACKLifecycleManager, AckStage } from '../src/internal/runtime/ackLifecycle.js';
import { ActivityBuffer } from '../src/internal/runtime/activityBuffer.js';
import { RuntimePersistence } from '../src/runtime/persistenceAdapter.js';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

class StubRouter {
  async sendMessage() {}
}

function makeStream() {
  const e = new EventEmitter();
  // @ts-expect-error minimal compliance
  return e;
}

describe('integration smoke', () => {
  it('routes message, observes ACK, and persists state', async () => {
    const env = buildEnvelope({ producer_id: 'p', message_type: MessageType.DATA });
    const router = new StubRouter() as any;
    const stream = makeStream();
    const acks = new ACKLifecycleManager();
    const buf = new ActivityBuffer();
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'sw4rm-js-'));
    const persist = RuntimePersistence.json(dir, buf, acks);
    // Simulate ACK
    setTimeout(() => { (stream as any).emit('data', { msg: { ack_for_message_id: env.message_id, ack_stage: AckStage.RECEIVED } }); }, 10);
    await sendMessageWithAck(router, stream as any, env, acks, (i)=>({ackFor: i.msg?.ack_for_message_id, stage: i.msg?.ack_stage}), { receivedTimeoutMs: 200 });
    expect(acks.get(env.message_id)?.stage).toBe(AckStage.RECEIVED);
    await persist.save();
    const acks2 = new ACKLifecycleManager();
    const buf2 = new ActivityBuffer();
    const persist2 = RuntimePersistence.json(dir, buf2, acks2);
    await persist2.load();
    expect(acks2.get(env.message_id)?.stage).toBe(AckStage.RECEIVED);
  });
});

