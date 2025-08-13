import { describe, it, expect } from 'vitest';
import { buildEnvelope, MessageType } from '../src/internal/envelope.js';

describe('envelope builder', () => {
  it('requires content_type when payload is present', () => {
    expect(() => buildEnvelope({ producer_id: 'a', message_type: MessageType.DATA, payload: new Uint8Array([1]) })).toThrow();
  });
  it('computes content_length and sets defaults', () => {
    const env = buildEnvelope({ producer_id: 'a', message_type: MessageType.DATA, payload: new Uint8Array([1,2,3]), content_type: 'application/octet-stream' });
    expect(env.content_length).toBe(3);
    expect(env.message_id).toBeTruthy();
    expect(env.correlation_id).toBeTruthy();
  });
});

