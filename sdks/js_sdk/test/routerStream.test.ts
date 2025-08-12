import { describe, it, expect } from 'vitest';
import { EventEmitter } from 'node:events';
import { createResilientIncomingStream } from '../src/runtime/streams.js';

class FakeRouter {
  calls = 0;
  streamIncoming() {
    this.calls++;
    const emitter = new EventEmitter();
    // First call errors, second call emits data
    if (this.calls === 1) {
      setTimeout(() => emitter.emit('error', new Error('boom')), 5);
    } else {
      setTimeout(() => emitter.emit('data', { msg: { message_id: 'm1' } }), 10);
    }
    // minimal API surface used by consumer
    // @ts-expect-error compatible enough for test
    return emitter;
  }
}

describe('createResilientIncomingStream', () => {
  it('reconnects on error and emits data', async () => {
    const router = new FakeRouter() as any;
    const emitter = createResilientIncomingStream(router, 'agent-1', { initialBackoffMs: 1, maxBackoffMs: 2 });
    let reconnected = false;
    let gotData = false;
    emitter.on('reconnecting', () => { reconnected = true; });
    await new Promise<void>((resolve) => {
      emitter.on('data', (_: any) => { gotData = true; resolve(); });
    });
    expect(reconnected).toBe(true);
    expect(gotData).toBe(true);
  });
});

