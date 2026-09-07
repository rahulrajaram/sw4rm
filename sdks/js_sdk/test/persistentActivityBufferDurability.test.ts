import { afterEach, describe, expect, it, vi } from 'vitest';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {
  ActivityBufferLoadError,
  JSONFilePersistence,
  PersistentActivityBuffer,
} from '../src/persistentActivityBuffer.js';

const tempDirs: string[] = [];
function tempFile(): string {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'sw4rm-js-buffer-'));
  tempDirs.push(dir);
  return path.join(dir, 'activity.json');
}

afterEach(() => {
  for (const dir of tempDirs.splice(0)) fs.rmSync(dir, { recursive: true, force: true });
});

describe('PersistentActivityBuffer durability', () => {
  it.each(['recordIncoming', 'recordOutgoing'] as const)('restores retries without duplicate ordering through %s', (method) => {
    const file = tempFile();
    const buffer = new PersistentActivityBuffer({ persistence: new JSONFilePersistence(file), maxItems: 1 });
    buffer[method]({ message_id: 'm1', payload: 'first' });
    buffer[method]({ message_id: 'm1', payload: 'retry' });
    buffer.flush();
    const restored = new PersistentActivityBuffer({ persistence: new JSONFilePersistence(file), maxItems: 1 });
    expect(restored.size).toBe(1);
    expect(restored.get('m1')?.envelope.payload).toBe('retry');
  });

  it.each([
    {},
    { records: {}, order: ['lost'] },
    { records: { m1: { message_id: 'm1', direction: 'in', envelope: {} } }, order: [] },
    { records: { m1: { message_id: 'm1', direction: 'in', envelope: {} } }, order: ['m1', 'm1'] },
    { records: { m1: { message_id: 'wrong', direction: 'in', envelope: {} } }, order: ['m1'] },
    { records: { m1: { message_id: 'm1', direction: 'in', envelope: { payload: '!!!', _payload_is_b64: true } } }, order: ['m1'] },
  ])('rejects structurally damaged snapshots: %j', (snapshot) => {
    const file = tempFile();
    fs.writeFileSync(file, JSON.stringify(snapshot));
    expect(() => new JSONFilePersistence(file).load()).toThrow(ActivityBufferLoadError);
  });

  it('uses a durable atomic file and round-trips byte payloads', () => {
    const file = tempFile();
    const first = new PersistentActivityBuffer({ persistence: new JSONFilePersistence(file) });
    first.recordOutgoing({ message_id: 'm1', idempotency_token: 'token-1', payload: Uint8Array.from([1, 2, 255]) });
    first.flush();

    const second = new PersistentActivityBuffer({ persistence: new JSONFilePersistence(file) });
    const record = second.getByIdempotencyToken('token-1');
    expect(record?.envelope.payload).toEqual(Uint8Array.from([1, 2, 255]));
    expect(fs.existsSync(`${file}.tmp`)).toBe(false);
  });

  it('writes the shared _bytes_fields marker Python snapshots use (R23)', () => {
    const file = tempFile();
    const first = new PersistentActivityBuffer({ persistence: new JSONFilePersistence(file) });
    first.recordOutgoing({ message_id: 'm1', payload: Uint8Array.from([9, 8, 7]) });
    first.flush();

    const snapshot = JSON.parse(fs.readFileSync(file, 'utf-8'));
    const envelope = snapshot.records.m1.envelope;
    expect(envelope._bytes_fields).toEqual(['payload']);
    expect(envelope._payload_is_b64).toBeUndefined();
  });

  it('loads Python-written snapshots carrying the shared _bytes_fields marker (R23)', () => {
    const file = tempFile();
    // Shape produced by sw4rm.persistence._encode_envelope (Python).
    const pythonSnapshot = {
      records: {
        m1: {
          message_id: 'm1',
          direction: 'in',
          envelope: { payload: Buffer.from([10, 20, 30]).toString('base64'), _bytes_fields: ['payload'] },
        },
      },
      order: ['m1'],
    };
    fs.writeFileSync(file, JSON.stringify(pythonSnapshot));

    const restored = new PersistentActivityBuffer({ persistence: new JSONFilePersistence(file) });
    expect(restored.get('m1')?.envelope.payload).toEqual(Uint8Array.from([10, 20, 30]));
  });

  it('rejects Python-written snapshots with an invalid byte-field marker', () => {
    const file = tempFile();
    const damaged = {
      records: { m1: { message_id: 'm1', direction: 'in', envelope: { payload: 'AAA=', _bytes_fields: ['nope'] } } },
      order: ['m1'],
    };
    fs.writeFileSync(file, JSON.stringify(damaged));
    expect(() => new JSONFilePersistence(file).load()).toThrow(ActivityBufferLoadError);
  });

  it('fails closed on corrupt state by default', () => {
    const file = tempFile();
    fs.writeFileSync(file, '{"records":');
    expect(() => new PersistentActivityBuffer({ persistence: new JSONFilePersistence(file) })).toThrow(ActivityBufferLoadError);
  });

  it('allows an explicit degraded empty start and logs it loudly', () => {
    const file = tempFile();
    fs.writeFileSync(file, '{"records":');
    const error = vi.spyOn(console, 'error').mockImplementation(() => undefined);
    const buffer = new PersistentActivityBuffer({
      persistence: new JSONFilePersistence(file),
      loadFailureMode: 'empty',
    });
    expect(buffer.size).toBe(0);
    expect(error).toHaveBeenCalled();
    error.mockRestore();
  });

  it('propagates save failures so durability is observable', () => {
    const persistence = {
      load: () => ({ records: {}, order: [] }),
      save: () => { throw new Error('disk full'); },
      clear: () => undefined,
    };
    const buffer = new PersistentActivityBuffer({ persistence });
    buffer.recordOutgoing({ message_id: 'm1' });
    expect(() => buffer.flush()).toThrow('disk full');
  });
});
