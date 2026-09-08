import { describe, it, expect } from 'vitest';
import { computeIdempotencyToken } from '../src/internal/idempotency.js';
import { buildEnvelope, MessageType } from '../src/internal/envelope.js';

describe('idempotency', () => {
  it('computes stable token for same input', () => {
    const a = computeIdempotencyToken({ producer_id: 'p', operation: 'router:send', canonical_bytes: new TextEncoder().encode('X') });
    const b = computeIdempotencyToken({ producer_id: 'p', operation: 'router:send', canonical_bytes: new TextEncoder().encode('X') });
    expect(a).toBe(b);
  });
  it('preserves token across retries while message_id changes', () => {
    const token = 'tok-1';
    const e1 = buildEnvelope({ producer_id: 'p', message_type: MessageType.DATA, idempotency_token: token });
    const e2 = buildEnvelope({ producer_id: 'p', message_type: MessageType.DATA, idempotency_token: token });
    expect(e1.idempotency_token).toBe(token);
    expect(e2.idempotency_token).toBe(token);
    expect(e1.message_id).not.toBe(e2.message_id);
  });
  it('rejects LF in producer_id and operation (bytes-v1 parsing ambiguity)', () => {
    // R43: LF is the digest field separator; an embedded LF would make the
    // prefix ambiguous, so computeIdempotencyToken must reject it loudly.
    expect(() => computeIdempotencyToken({ producer_id: 'agent\nx', operation: 'work', canonical_bytes: new Uint8Array(0) }))
      .toThrow(TypeError);
    expect(() => computeIdempotencyToken({ producer_id: 'agent', operation: 'tool:call\nextra', canonical_bytes: new Uint8Array(0) }))
      .toThrow(TypeError);
  });
});

