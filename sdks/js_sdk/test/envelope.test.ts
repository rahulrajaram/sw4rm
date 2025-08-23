import { describe, it, expect } from 'vitest';
import { buildEnvelope, MessageType } from '../src/internal/envelope.js';

describe('envelope builder', () => {
  it('sets default content_type to application/json when no payload', () => {
    const env = buildEnvelope({ producer_id: 'a', message_type: MessageType.DATA });
    expect(env.content_type).toBe('application/json');
    expect(env.sequence_number).toBe(1); // Aligned with Python/Rust
    expect(env.hlc_timestamp).toBeTruthy(); // Always set
  });
  
  it('sets content_type to application/octet-stream for payload without explicit content_type', () => {
    const env = buildEnvelope({ producer_id: 'a', message_type: MessageType.DATA, payload: new Uint8Array([1,2,3]) });
    expect(env.content_type).toBe('application/octet-stream');
    expect(env.content_length).toBe(3);
  });
  
  it('respects explicit content_type when provided', () => {
    const env = buildEnvelope({ producer_id: 'a', message_type: MessageType.DATA, payload: new Uint8Array([1,2,3]), content_type: 'application/custom' });
    expect(env.content_type).toBe('application/custom');
    expect(env.content_length).toBe(3);
  });
  
  it('computes content_length and sets all required defaults', () => {
    const env = buildEnvelope({ producer_id: 'a', message_type: MessageType.DATA, payload: new Uint8Array([1,2,3]), content_type: 'application/octet-stream' });
    expect(env.content_length).toBe(3);
    expect(env.message_id).toBeTruthy();
    expect(env.correlation_id).toBeTruthy();
    expect(env.sequence_number).toBe(1); // Fixed from 0 to align with Python/Rust
    expect(env.content_type).toBe('application/octet-stream');
    expect(env.hlc_timestamp).toBeTruthy(); // Always present
  });
});

