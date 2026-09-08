// Persistent Activity Buffer with Three-ID model support
// Tracks inbound/outbound envelopes by message_id and records ACK progression.
// Supports deduplication via idempotency_token, workflow linking via correlation_id.

import {
  closeSync,
  existsSync,
  fsyncSync,
  mkdirSync,
  openSync,
  readFileSync,
  renameSync,
  unlinkSync,
  writeFileSync,
} from 'node:fs';
import { dirname } from 'node:path';
import {
  EnvelopeState,
  AckStage,
} from './constants/index.js';
import { ErrorCode, BufferFullError } from './internal/errorMapping.js';

export interface EnvelopeRecord {
  message_id: string;
  direction: 'in' | 'out';
  envelope: Record<string, unknown>;
  ts_ms: number;
  ack_stage: number;
  error_code: number;
  ack_note: string;
}

export interface PersistenceBackend {
  load(): { records: Record<string, EnvelopeRecord>; order: string[] };
  save(records: Record<string, EnvelopeRecord>, order: string[]): void;
  clear(): void;
}

/** Raised when an existing activity file cannot be safely restored. */
export class ActivityBufferLoadError extends Error {
  constructor(message: string, options?: { cause?: unknown }) {
    super(message, options);
    this.name = 'ActivityBufferLoadError';
  }
}

const byteFields = ['payload', 'audit_proof'] as const;
// Shared snapshot marker written and read by the Python persistence layer.
const BYTE_FIELDS_MARKER = '_bytes_fields';

function encodeEnvelope(envelope: Record<string, unknown>): Record<string, unknown> {
  const encoded = { ...envelope };
  const marked: string[] = [];
  for (const field of byteFields) {
    const value = encoded[field];
    if (value instanceof Uint8Array) {
      encoded[field] = Buffer.from(value).toString('base64');
      marked.push(field);
    }
  }
  // Write the shared `_bytes_fields` representation so Python round-trips
  // JS snapshots natively (the legacy per-field marker remains only a
  // read-compatibility path).
  if (marked.length > 0) encoded[BYTE_FIELDS_MARKER] = marked;
  return encoded;
}

function decodeEnvelope(envelope: Record<string, unknown>): Record<string, unknown> {
  const decoded = { ...envelope };
  const marked: string[] = [];
  // Shared `_bytes_fields` marker (Python-written snapshots).
  const shared = decoded[BYTE_FIELDS_MARKER];
  if (shared !== undefined) {
    if (!Array.isArray(shared) ||
        !shared.every((field) => typeof field === 'string' &&
                               (byteFields as readonly string[]).includes(field))) {
      throw new Error('invalid envelope byte-field marker');
    }
    marked.push(...shared);
    delete decoded[BYTE_FIELDS_MARKER];
  }
  // Legacy per-field markers remain readable for older JS snapshots.
  for (const field of byteFields) {
    const legacy = `_${field}_is_b64`;
    const marker = decoded[legacy];
    if (marker !== undefined && typeof marker !== 'boolean') {
      throw new Error(`invalid byte marker for ${field}`);
    }
    if (marker === true) marked.push(field);
    delete decoded[legacy];
  }
  for (const field of [...new Set(marked)]) {
    const value = decoded[field];
    if (typeof value !== 'string' || Buffer.from(value, 'base64').toString('base64') !== value) {
      throw new Error(`invalid base64 for ${field}`);
    }
    decoded[field] = Uint8Array.from(Buffer.from(value, 'base64'));
  }
  return decoded;
}

/**
 * JSON file persistence backend.
 */
export class JSONFilePersistence implements PersistenceBackend {
  constructor(private filePath: string = 'sw4rm_activity.json') {}

  load(): { records: Record<string, EnvelopeRecord>; order: string[] } {
    if (!existsSync(this.filePath)) {
      return { records: {}, order: [] };
    }
    try {
      const raw = readFileSync(this.filePath, 'utf-8');
      const data: unknown = JSON.parse(raw);
      if (!data || typeof data !== 'object' || Array.isArray(data)) {
        throw new Error('top-level value must be an object');
      }
      const value = data as { records?: unknown; order?: unknown };
      const rawRecords = value.records;
      const rawOrder = value.order;
      if (typeof rawRecords !== 'object' || rawRecords === null || Array.isArray(rawRecords)) {
        throw new Error('records must be an object');
      }
      if (!Array.isArray(rawOrder) || !rawOrder.every((id) => typeof id === 'string')) {
        throw new Error('order must be an array of message IDs');
      }
      const records: Record<string, EnvelopeRecord> = Object.create(null);
      for (const [messageId, rawRecord] of Object.entries(rawRecords)) {
        if (!rawRecord || typeof rawRecord !== 'object' || Array.isArray(rawRecord)) {
          throw new Error(`record ${messageId} must be an object`);
        }
        const record = rawRecord as Record<string, unknown>;
        if (record.message_id !== messageId || !['in', 'out'].includes(record.direction as string)) {
          throw new Error(`record ${messageId} has invalid identity or direction`);
        }
        if (!record.envelope || typeof record.envelope !== 'object' || Array.isArray(record.envelope)) {
          throw new Error(`record ${messageId} has no envelope object`);
        }
        records[messageId] = {
          ...(record as unknown as EnvelopeRecord),
          envelope: decodeEnvelope(record.envelope as Record<string, unknown>),
        };
      }
      if (new Set(rawOrder).size !== rawOrder.length || rawOrder.length !== Object.keys(records).length ||
          !rawOrder.every((id) => Object.hasOwn(records, id))) {
        throw new Error('order and records must contain the same distinct message IDs');
      }
      return { records, order: rawOrder };
    } catch (error) {
      if (error instanceof ActivityBufferLoadError) throw error;
      throw new ActivityBufferLoadError(
        `Activity buffer persistence file is corrupted: ${this.filePath}: ${error instanceof Error ? error.message : String(error)}`,
        { cause: error },
      );
    }
  }

  save(records: Record<string, EnvelopeRecord>, order: string[]): void {
    const dir = dirname(this.filePath);
    if (dir && !existsSync(dir)) {
      mkdirSync(dir, { recursive: true });
    }
    const serializableRecords: Record<string, EnvelopeRecord> = {};
    for (const [messageId, record] of Object.entries(records)) {
      serializableRecords[messageId] = {
        ...record,
        envelope: encodeEnvelope(record.envelope),
      };
    }
    const tempPath = `${this.filePath}.tmp`;
    try {
      const fd = openSync(tempPath, 'w');
      try {
        writeFileSync(fd, JSON.stringify({ records: serializableRecords, order, version: '1.0' }, null, 2));
        fsyncSync(fd);
      } finally {
        closeSync(fd);
      }
      renameSync(tempPath, this.filePath);
      const dirFd = openSync(dir || '.', 'r');
      try {
        fsyncSync(dirFd);
      } finally {
        closeSync(dirFd);
      }
    } catch (error) {
      if (existsSync(tempPath)) unlinkSync(tempPath);
      throw error;
    }
  }

  clear(): void {
    if (existsSync(this.filePath)) {
      unlinkSync(this.filePath);
    }
  }
}

/**
 * Persistent Activity Buffer with Three-ID model support.
 *
 * Tracks inbound/outbound envelopes by message_id and records ACK progression.
 * Supports multiple persistence backends (JSON file, etc.) and provides
 * reconciliation on startup to restore previous state.
 *
 * When the buffer is full, new records are REJECTED with BufferFullError
 * per spec compliance (not silently pruned).
 */
export class PersistentActivityBuffer {
  private byId: Map<string, EnvelopeRecord> = new Map();
  private byIdempotencyToken: Map<string, string> = new Map(); // token -> message_id
  private order: string[] = [];
  private maxItems: number;
  private persistence: PersistenceBackend;
  private dedupWindowS: number;
  private dirty = false;
  private loadFailureMode: 'raise' | 'empty';

  constructor(opts?: {
    maxItems?: number;
    persistence?: PersistenceBackend;
    dedupWindowS?: number;
    loadFailureMode?: 'raise' | 'empty';
  }) {
    this.maxItems = opts?.maxItems ?? 10000;
    this.persistence = opts?.persistence ?? new JSONFilePersistence();
    this.dedupWindowS = opts?.dedupWindowS ?? 3600;
    this.loadFailureMode = opts?.loadFailureMode ?? 'raise';
    if (this.loadFailureMode !== 'raise' && this.loadFailureMode !== 'empty') {
      throw new TypeError("loadFailureMode must be 'raise' or 'empty'");
    }
    this.loadFromPersistence();
  }

  private loadFromPersistence(): void {
    try {
      const { records, order } = this.persistence.load();
      this.byId = new Map(Object.entries(records));
      this.order = order.filter((messageId) => this.byId.has(messageId));

      // Rebuild idempotency token index
      for (const [mid, rec] of this.byId) {
        const token = (rec.envelope as any)?.idempotency_token;
        if (token) {
          this.byIdempotencyToken.set(token, mid);
        }
      }
    } catch (error) {
      // Only a classified corrupt-file error may opt into degraded startup;
      // backend availability/configuration failures must remain visible.
      if (!(error instanceof ActivityBufferLoadError)) throw error;
      if (this.loadFailureMode !== 'empty') throw error;
      console.error(
        '[ActivityBuffer] CORRUPTED persistence; starting DEGRADED with an empty buffer — recovery state was not restored',
        error,
      );
      this.byId = new Map();
      this.byIdempotencyToken = new Map();
      this.order = [];
    }
  }

  private saveToPersistence(): void {
    if (!this.dirty) return;
    const records: Record<string, EnvelopeRecord> = {};
    for (const [k, v] of this.byId) {
      records[k] = v;
    }
    this.persistence.save(records, this.order);
    this.dirty = false;
  }

  private checkCapacity(): void {
    if (this.byId.size >= this.maxItems) {
      throw new BufferFullError(
        `Activity buffer is full (max ${this.maxItems} items). Reject per spec.`,
        ErrorCode.BUFFER_FULL
      );
    }
  }

  private cleanupExpiredDedupEntries(): void {
    const nowMs = Date.now();
    const windowMs = this.dedupWindowS * 1000;
    const expired: string[] = [];

    for (const [token, mid] of this.byIdempotencyToken) {
      const rec = this.byId.get(mid);
      if (rec && (nowMs - rec.ts_ms) > windowMs) {
        expired.push(token);
      }
    }

    for (const token of expired) {
      this.byIdempotencyToken.delete(token);
    }
  }

  /**
   * Record an incoming envelope. Throws BufferFullError if buffer is at capacity.
   */
  recordIncoming(envelope: Record<string, unknown>): EnvelopeRecord {
    const mid = String(envelope.message_id ?? '');
    if (!this.byId.has(mid)) {
      this.checkCapacity();
      this.order.push(mid);
    }
    const rec: EnvelopeRecord = {
      message_id: mid,
      direction: 'in',
      envelope,
      ts_ms: Date.now(),
      ack_stage: AckStage.ACK_STAGE_UNSPECIFIED,
      error_code: ErrorCode.ERROR_CODE_UNSPECIFIED,
      ack_note: '',
    };

    this.byId.set(mid, rec);

    const token = (envelope as any).idempotency_token;
    if (token) {
      this.byIdempotencyToken.set(token, mid);
    }

    this.cleanupExpiredDedupEntries();
    this.dirty = true;
    return rec;
  }

  /**
   * Record an outgoing envelope. Throws BufferFullError if buffer is at capacity.
   */
  recordOutgoing(envelope: Record<string, unknown>): EnvelopeRecord {
    const mid = String(envelope.message_id ?? '');
    if (!this.byId.has(mid)) {
      this.checkCapacity();
      this.order.push(mid);
    }
    const rec: EnvelopeRecord = {
      message_id: mid,
      direction: 'out',
      envelope,
      ts_ms: Date.now(),
      ack_stage: AckStage.ACK_STAGE_UNSPECIFIED,
      error_code: ErrorCode.ERROR_CODE_UNSPECIFIED,
      ack_note: '',
    };

    this.byId.set(mid, rec);

    const token = (envelope as any).idempotency_token;
    if (token) {
      this.byIdempotencyToken.set(token, mid);
    }

    this.cleanupExpiredDedupEntries();
    this.dirty = true;
    return rec;
  }

  /**
   * Process an ACK for a previously recorded message.
   */
  ack(ackMsg: {
    ack_for_message_id: string;
    ack_stage?: number;
    error_code?: number;
    note?: string;
  }): EnvelopeRecord | undefined {
    const target = String(ackMsg.ack_for_message_id);
    const rec = this.byId.get(target);
    if (rec) {
      rec.ack_stage = ackMsg.ack_stage ?? AckStage.ACK_STAGE_UNSPECIFIED;
      rec.error_code = ackMsg.error_code ?? ErrorCode.ERROR_CODE_UNSPECIFIED;
      rec.ack_note = ackMsg.note ?? '';
      this.dirty = true;
    }
    return rec;
  }

  /** Get record by message ID. */
  get(messageId: string): EnvelopeRecord | undefined {
    return this.byId.get(messageId);
  }

  /** Get record by idempotency token (for deduplication). */
  getByIdempotencyToken(token: string): EnvelopeRecord | undefined {
    this.cleanupExpiredDedupEntries();
    const mid = this.byIdempotencyToken.get(token);
    if (mid) return this.byId.get(mid);
    return undefined;
  }

  /** Get all un-ACKed records. */
  unacked(): EnvelopeRecord[] {
    return [...this.byId.values()].filter(
      (r) =>
        r.ack_stage === AckStage.ACK_STAGE_UNSPECIFIED ||
        r.ack_stage === AckStage.RECEIVED ||
        r.ack_stage === AckStage.READ
    );
  }

  /** Get N most recent records. */
  recent(n = 50): EnvelopeRecord[] {
    const ids = this.order.slice(-n);
    return ids.map((id) => this.byId.get(id)).filter(Boolean) as EnvelopeRecord[];
  }

  /** Update envelope state for a message. */
  updateState(messageId: string, newState: EnvelopeState): EnvelopeRecord | undefined {
    const rec = this.byId.get(messageId);
    if (rec) {
      (rec.envelope as any).state = newState;
      this.dirty = true;
    }
    return rec;
  }

  /** Return unacked outgoing messages for reconciliation. */
  reconcile(): EnvelopeRecord[] {
    return this.unacked().filter((r) => r.direction === 'out');
  }

  /** Force save to persistence. */
  flush(): void {
    this.dirty = true;
    this.saveToPersistence();
  }

  /** Clear all records. */
  clear(): void {
    this.byId.clear();
    this.byIdempotencyToken.clear();
    this.order = [];
    this.persistence.clear();
    this.dirty = false;
  }

  /** Get the count of records. */
  get size(): number {
    return this.byId.size;
  }
}
