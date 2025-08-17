import { describe, it, expect } from 'vitest';
import { parseNegotiationEvent, decodeBase64 } from '../src/runtime/negotiationEvents.js';

describe('negotiation events', () => {
  it('parses policy event and decodes base64 where present', () => {
    const json = JSON.stringify({
      kind: 'policy',
      ts: '2025-08-17T10:00:00Z',
      negotiation_id: 'neg-1',
      policy: { max_rounds: 4, score_threshold: 0.8 }
    });
    const evt = parseNegotiationEvent(json) as any;
    expect(evt.kind).toBe('policy');
    expect(evt.negotiation_id).toBe('neg-1');
    expect(evt.policy.max_rounds).toBe(4);
  });

  it('parses propose and decodes payload_b64', () => {
    const json = JSON.stringify({ kind: 'propose', from: 'a', ct: 'text/plain', payload_b64: 'SGk=' });
    const evt = parseNegotiationEvent(json) as any;
    const bytes = decodeBase64(evt.payload_b64);
    expect(bytes).toBeDefined();
    expect(new TextDecoder().decode(bytes!)).toBe('Hi');
  });
});

