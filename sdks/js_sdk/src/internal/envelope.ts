// Envelope builder aligned with documentation/protocol/spec.md §11
import crypto from 'node:crypto';

export type Timestamp = { seconds: number; nanos: number };

export enum MessageType {
  MESSAGE_TYPE_UNSPECIFIED = 0,
  CONTROL = 1,
  DATA = 2,
  HEARTBEAT = 3,
  NOTIFICATION = 4,
  ACKNOWLEDGEMENT = 5,
  HITL_INVOCATION = 6,
  WORKTREE_CONTROL = 7,
  NEGOTIATION = 8,
  TOOL_CALL = 9,
  TOOL_RESULT = 10,
  TOOL_ERROR = 11,
}

export interface EnvelopeInput {
  producer_id: string;
  message_type: MessageType;
  payload?: Uint8Array | Buffer;
  content_type?: string; // required if payload present
  correlation_id?: string; // default: generated UUIDv4
  idempotency_token?: string; // optional but preserved across retries
  sequence_number?: number; // monotonic per producer stream
  retry_count?: number; // incremented by caller on retry
  repo_id?: string;
  worktree_id?: string;
  hlc_timestamp?: string;
  ttl_ms?: number;
  timestamp?: Date; // default now (UTC)
  state?: number; // EnvelopeState (default: CREATED = 1)
  effective_policy_id?: string; // ID of effective policy governing this operation
  audit_proof?: Uint8Array; // cryptographic proof for audit trail
  audit_policy_id?: string; // ID of audit policy governing this envelope
}

export interface EnvelopeBuilt {
  message_id: string;
  idempotency_token?: string;
  producer_id: string;
  correlation_id: string;
  sequence_number: number;
  retry_count: number;
  message_type: MessageType;
  content_type: string; // Always present (aligns with Python/Rust)
  content_length?: number;
  repo_id?: string;
  worktree_id?: string;
  hlc_timestamp: string; // Always present (aligns with Python/Rust)
  ttl_ms?: number;
  timestamp: Timestamp;
  payload?: Uint8Array;
  state: number; // EnvelopeState lifecycle
  effective_policy_id: string; // effective policy ID (empty if not set)
  audit_proof: Uint8Array; // audit proof bytes (empty if not set)
  audit_policy_id: string; // audit policy ID (empty if not set)
}

export function nowTimestamp(date = new Date()): Timestamp {
  const ms = date.getTime();
  const seconds = Math.floor(ms / 1000);
  const nanos = (ms % 1000) * 1e6;
  return { seconds, nanos };
}

/**
 * Generate a stub HLC timestamp in the canonical format `HLC:<wall>:<logical>:<node>`.
 *
 * Per spec section 4, the HLC format combines wall-clock time (Unix microseconds),
 * a logical counter (always 0 in this stub), and a node identifier (hostname).
 * Full HLC implementations should increment the logical counter on concurrent
 * events within the same microsecond.
 */
export function nowHlcStub(date = new Date()): string {
  const wallUs = date.getTime() * 1000; // milliseconds -> microseconds
  let node = 'unknown';
  try {
    // Node.js environment
    const os = require('node:os');
    node = os.hostname() || 'unknown';
  } catch {
    node = 'browser';
  }
  return `HLC:${wallUs}:0:${node}`;
}

function uuidv4(): string {
  if (typeof (crypto as any).randomUUID === 'function') {
    return (crypto as any).randomUUID();
  }
  // Fallback RFC4122 v4
  const buf = crypto.randomBytes(16);
  buf[6] = (buf[6] & 0x0f) | 0x40;
  buf[8] = (buf[8] & 0x3f) | 0x80;
  const hex = [...buf].map(b => b.toString(16).padStart(2, '0'));
  return (
    hex.slice(0, 4).join('') + '-' +
    hex.slice(4, 6).join('') + '-' +
    hex.slice(6, 8).join('') + '-' +
    hex.slice(8, 10).join('') + '-' +
    hex.slice(10, 16).join('')
  );
}

export function buildEnvelope(input: EnvelopeInput): EnvelopeBuilt {
  const hasPayload = input.payload !== undefined;
  // Always set content_type to align with Python/Rust behavior
  const content_type = input.content_type ?? 'application/json';

  const message_id = uuidv4(); // new per attempt
  const correlation_id = input.correlation_id ?? uuidv4();
  const sequence_number = input.sequence_number ?? 1;
  const retry_count = input.retry_count ?? 0;
  const ts = nowTimestamp(input.timestamp ?? new Date());
  const hlc_timestamp = input.hlc_timestamp ?? nowHlcStub(input.timestamp);

  const built: EnvelopeBuilt = {
    message_id,
    idempotency_token: input.idempotency_token,
    producer_id: input.producer_id,
    correlation_id,
    sequence_number,
    retry_count,
    message_type: input.message_type,
    content_type, // Always set content_type (aligns with Python/Rust)
    repo_id: input.repo_id,
    worktree_id: input.worktree_id,
    hlc_timestamp, // Always set hlc_timestamp (aligns with Python/Rust)
    ttl_ms: input.ttl_ms,
    timestamp: ts,
    state: input.state ?? 1, // EnvelopeState.CREATED
    effective_policy_id: input.effective_policy_id ?? '',
    audit_proof: input.audit_proof ?? new Uint8Array(0),
    audit_policy_id: input.audit_policy_id ?? '',
  };

  if (hasPayload) {
    const payload = input.payload instanceof Uint8Array ? input.payload : new Uint8Array(input.payload as any);
    built.payload = payload;
    built.content_length = payload.byteLength;
    // Override content_type for binary payloads if not explicitly set, like Rust does
    if (!input.content_type) {
      built.content_type = 'application/octet-stream';
    }
  }

  return built;
}

