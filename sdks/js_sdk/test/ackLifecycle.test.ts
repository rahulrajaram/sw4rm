import { describe, it, expect } from 'vitest';
import { ACKLifecycleManager, AckStage } from '../src/internal/runtime/ackLifecycle.js';

describe('ACK lifecycle', () => {
  it('tracks and reconciles', () => {
    const m = new ACKLifecycleManager();
    m.mark('mid', AckStage.RECEIVED);
    expect(m.get('mid')?.stage).toBe(AckStage.RECEIVED);
    m.reconcileLateAck('mid', AckStage.FULFILLED);
    expect(m.get('mid')?.stage).toBe(AckStage.FULFILLED);
  });
});

