import crypto from 'node:crypto';

export interface IdempotencyInput {
  producer_id: string;
  operation: string; // e.g., 'router:send', 'tool:call'
  canonical_bytes: Uint8Array | Buffer; // deterministic serialization of params
}

export function computeIdempotencyToken(input: IdempotencyInput): string {
  // LF is the bytes-v1 digest field separator: an embedded LF in either
  // field would make the prefix ambiguous, so reject it loudly (R43).
  if (input.producer_id.includes('\n') || input.operation.includes('\n')) {
    throw new TypeError(
      'producer_id/operation must not contain LF: the bytes-v1 digest prefix uses LF as a field separator');
  }
  const h = crypto.createHash('sha256');
  h.update(input.producer_id);
  h.update('\n');
  h.update(input.operation);
  h.update('\n');
  h.update(Buffer.from(input.canonical_bytes));
  const hash16 = h.digest('hex').slice(0, 16);
  return `${input.producer_id}:${input.operation}:${hash16}`;
}

