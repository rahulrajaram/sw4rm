// Persistent Activity Buffer with Three-ID model support
// Tracks inbound/outbound envelopes by message_id and records ACK progression.
// Supports deduplication via idempotency_token, workflow linking via correlation_id.

import { readFileSync, writeFileSync, existsSync, mkdirSync } from 'node:fs';
import { dirname } from 'node:path';
import {
  EnvelopeState,
  isTerminalEnvelopeState,
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

/**
 * JSON file persistence backend.
 */
export class JSONFilePersistence implements PersistenceBackend {
  constructor(private filePath: string = 'sw4rm_activity.json') {}

  load(): { records: Record<string, EnvelopeRecord>; order: string[] } {
    if (!existsSync(this.filePath)) {
      return { records: {}, order: [] };
    }
    const raw = readFileSync(this.filePath, 'utf-8');
    const data = JSON.parse(raw);
    return {
      records: data.records ?? {},
      order: data.order ?? [],
    };
  }

  save(records: Record<string, EnvelopeRecord>, order: string[]): void {
    const dir = dirname(this.filePath);
    if (dir && !existsSync(dir)) {
      mkdirSync(dir, { recursive: true });
    }
    writeFileSync(this.filePath, JSON.stringify({ records, order, version: '1.0' }, null, 2));
  }

  clear(): void {
    if (existsSync(this.filePath)) {
      writeFileSync(this.filePath, JSON.stringify({ records: {}, order: [], version: '1.0' }));
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

  constructor(opts?: {
    maxItems?: number;
    persistence?: PersistenceBackend;
    dedupWindowS?: number;
  }) {
    this.maxItems = opts?.maxItems ?? 10000;
    this.persistence = opts?.persistence ?? new JSONFilePersistence();
    this.dedupWindowS = opts?.dedupWindowS ?? 3600;
    this.loadFromPersistence();
  }

  private loadFromPersistence(): void {
    try {
      const { records, order } = this.persistence.load();
      this.byId = new Map(Object.entries(records));
      this.order = order;

      // Rebuild idempotency token index
      for (const [mid, rec] of this.byId) {
        const token = (rec.envelope as any)?.idempotency_token;
        if (token) {
          this.byIdempotencyToken.set(token, mid);
        }
      }
    } catch {
      this.byId = new Map();
      this.byIdempotencyToken = new Map();
      this.order = [];
    }
  }

  private saveToPersistence(): void {
    if (!this.dirty) return;
    try {
      const records: Record<string, EnvelopeRecord> = {};
      for (const [k, v] of this.byId) {
        records[k] = v;
      }
      this.persistence.save(records, this.order);
      this.dirty = false;
    } catch {
      // Persistence failure is non-fatal
    }
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
    this.checkCapacity();

    const mid = String(envelope.message_id ?? '');
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
    this.order.push(mid);

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
    this.checkCapacity();

    const mid = String(envelope.message_id ?? '');
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
    this.order.push(mid);

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
