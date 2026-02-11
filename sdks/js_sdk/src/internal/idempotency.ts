import crypto from 'node:crypto';

export interface IdempotencyInput {
  producer_id: string;
  operation: string; // e.g., 'router:send', 'tool:call'
  canonical_bytes: Uint8Array | Buffer; // deterministic serialization of params
}

export function computeIdempotencyToken(input: IdempotencyInput): string {
  const h = crypto.createHash('sha256');
  h.update(input.producer_id);
  h.update('\n');
  h.update(input.operation);
  h.update('\n');
  h.update(Buffer.from(input.canonical_bytes));
  const hash16 = h.digest('hex').slice(0, 16);
  return `${input.producer_id}:${input.operation}:${hash16}`;
}

