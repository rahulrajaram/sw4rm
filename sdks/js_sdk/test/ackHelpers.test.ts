import { describe, it, expect } from 'vitest';
import { EventEmitter } from 'node:events';
import { sendMessageWithAck } from '../src/runtime/ackHelpers.js';
import { ACKLifecycleManager, AckStage } from '../src/internal/runtime/ackLifecycle.js';

class StubRouter {
  calls = 0;
  async sendMessage() { this.calls++; }
}

function makeStream() {
  const e = new EventEmitter();
  // @ts-expect-error minimal compliance
  return e;
}

const extractor = (item: any) => ({ ackFor: item.msg?.ack_for_message_id, stage: item.msg?.ack_stage });

describe('sendMessageWithAck', () => {
  it('resolves when RECEIVED arrives', async () => {
    const router = new StubRouter() as any;
    const stream = makeStream();
    const ack = new ACKLifecycleManager();
    const env: any = { message_id: 'mid', correlation_id: 'c' };
    // Emit an ACK shortly after send
    setTimeout(() => {
      // @ts-expect-error EventEmitter
      (stream as any).emit('data', { msg: { ack_for_message_id: 'mid', ack_stage: AckStage.RECEIVED } });
    }, 10);
    await sendMessageWithAck(router, stream as any, env, ack, extractor, { receivedTimeoutMs: 200 });
    expect(ack.get('mid')?.stage).toBe(AckStage.RECEIVED);
  });

  it('times out if no ACK arrives', async () => {
    const router = new StubRouter() as any;
    const stream = makeStream();
    const ack = new ACKLifecycleManager();
    const env: any = { message_id: 'mid2', correlation_id: 'c' };
    await expect(sendMessageWithAck(router, stream as any, env, ack, extractor, { receivedTimeoutMs: 30 })).rejects.toBeTruthy();
    expect(ack.get('mid2')?.stage).toBe(AckStage.TIMED_OUT);
  });
});

