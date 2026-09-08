import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import * as protoLoader from '@grpc/proto-loader';
import type { ServiceDefinition } from '@grpc/grpc-js';
import { describe, expect, it } from 'vitest';
import { buildEnvelope, computeIdempotencyToken, MessageType } from '../src/index.js';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../..');
const vectors = JSON.parse(fs.readFileSync(path.join(root, 'tests/conformance_vectors/idempotency_vectors.json'), 'utf8')).vectors;

describe('portable envelope helpers', () => {
  for (const vector of vectors) {
    it(`idempotency ${vector.id}`, () => {
      const compute = () => computeIdempotencyToken({ producer_id: vector.producer_id, operation: vector.operation,
        canonical_bytes: Buffer.from(vector.canonical_hex, 'hex') });
      if (vector.rejected) {
        // R43: LF in producer/operation must be rejected, not hashed.
        expect(compute).toThrow(TypeError);
      } else {
        expect(compute()).toBe(vector.token);
      }
    });
  }
  it('keeps lineage, valid pre-epoch timestamps and uint64 precision through serialization', () => {
    const envelope = buildEnvelope({ producer_id: 'sender', message_type: MessageType.DATA,
      parent_correlation_id: 'parent', timestamp: new Date(-875), sequence_number: '18446744073709551615',
      payload: Buffer.from([0, 255]) });
    const definitions = protoLoader.loadSync(path.join(root, 'protos/router.proto'), { keepCase: true, longs: String });
    const method = (definitions['sw4rm.router.RouterService'] as ServiceDefinition).SendMessage;
    const actual = method.requestDeserialize(method.requestSerialize({ msg: envelope })).msg;
    expect(actual.parent_correlation_id).toBe('parent');
    expect(actual.sequence_number).toBe('18446744073709551615');
    expect(actual.timestamp).toEqual({ seconds: '-1', nanos: 125000000 });
    expect(actual.payload).toEqual(Buffer.from([0, 255]));
    expect(() => buildEnvelope({ producer_id: 'sender', message_type: MessageType.DATA,
      sequence_number: 2 ** 53 })).toThrow(/safe integer/);
  });
});
