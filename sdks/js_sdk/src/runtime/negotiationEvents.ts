export type NegotiationEventKind = 'open' | 'policy' | 'propose' | 'counter' | 'evaluate' | 'decide' | 'abort' | { unknown: string };

export interface NegotiationEventBase { kind: string; ts?: string }

export interface OpenEvent extends NegotiationEventBase { kind: 'open'; topic: string; corr: string }
export interface PolicyEvent extends NegotiationEventBase { kind: 'policy'; negotiation_id: string; profile?: string; policy: any }
export interface PayloadEventBase extends NegotiationEventBase { from: string; ct: string; payload_b64?: string }
export interface ProposeEvent extends PayloadEventBase { kind: 'propose' }
export interface CounterEvent extends PayloadEventBase { kind: 'counter' }
export interface EvaluateEvent extends NegotiationEventBase { kind: 'evaluate'; from: string; score?: number; notes?: string }
export interface DecideEvent extends NegotiationEventBase { kind: 'decide'; by: string; ct: string; result_b64?: string }
export interface AbortEvent extends NegotiationEventBase { kind: 'abort'; reason?: string }

export type NegotiationEvent = OpenEvent | PolicyEvent | ProposeEvent | CounterEvent | EvaluateEvent | DecideEvent | AbortEvent | NegotiationEventBase;

export function parseNegotiationEvent(json: string): NegotiationEvent {
  try {
    const obj = JSON.parse(json);
    if (!obj || typeof obj.kind !== 'string') return { kind: 'unknown', ...(obj || {}) } as any;
    return obj as NegotiationEvent;
  } catch {
    return { kind: 'unknown', ts: undefined } as any;
  }
}

export function decodeBase64(b64?: string): Uint8Array | undefined {
  if (!b64) return undefined;
  return new Uint8Array(Buffer.from(b64, 'base64'));
}

