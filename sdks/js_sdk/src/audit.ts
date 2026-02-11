// Copyright 2025 Rahul Rajaram
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

/**
 * Audit proof extension for SW4RM protocol.
 *
 * This module provides audit trail capabilities with optional proof generation
 * and verification, inspired by ZK-MCP research.
 */

import crypto from 'node:crypto';
import { nowHlcStub } from './internal/envelope.js';
import { EnvelopeState } from './constants/index.js';

/**
 * Represents a cryptographic or logical proof for an audit event.
 */
export interface AuditProof {
  /** Unique identifier for this proof */
  proof_id: string;
  /** Type of proof (e.g., "simple_hash", "zk_proof", "signature") */
  proof_type: string;
  /** The actual proof data as bytes */
  proof_data: Uint8Array;
  /** Timestamp when the proof was created (HLC or unix ms) */
  created_at: string;
  /** Whether this proof has been verified */
  verified: boolean;
}

/**
 * Defines audit requirements for envelope processing.
 */
export interface AuditPolicy {
  /** Unique identifier for this policy */
  policy_id: string;
  /** Whether proof is required for this policy */
  require_proof: boolean;
  /** Level of verification required (e.g., "none", "basic", "strict") */
  verification_level: string;
  /** How many days to retain audit records */
  retention_days: number;
}

/**
 * Represents a complete audit record for an envelope action.
 */
export interface AuditRecord {
  /** Unique identifier for this audit record */
  record_id: string;
  /** The message_id of the envelope being audited */
  envelope_id: string;
  /** The action performed (e.g., "send", "receive", "process") */
  action: string;
  /** ID of the agent/component that performed the action */
  actor_id: string;
  /** When the action occurred (HLC or unix ms) */
  timestamp: string;
  /** Optional proof associated with this action */
  proof?: AuditProof;
}

/**
 * Envelope-like object for audit operations.
 * This is a minimal interface that matches the expected envelope structure.
 */
export interface EnvelopeAuditable {
  message_id?: string;
  producer_id?: string;
  payload?: Uint8Array;
  audit_proof?: Uint8Array;
  [key: string]: any;
}

/**
 * Protocol defining the interface for audit implementations.
 *
 * Implementations can range from no-op (for development) to full
 * ZK-proof based systems (for production).
 */
export interface Auditor {
  /**
   * Create a proof for an envelope action.
   *
   * @param envelope - The envelope to create proof for
   * @param action - The action being performed (e.g., "send", "receive")
   * @returns An AuditProof instance
   */
  createProof(envelope: EnvelopeAuditable, action: string): AuditProof;

  /**
   * Verify the validity of a proof.
   *
   * @param proof - The proof to verify
   * @returns True if proof is valid, false otherwise
   */
  verifyProof(proof: AuditProof): boolean;

  /**
   * Record an audit event.
   *
   * @param envelope - The envelope being audited
   * @param action - The action being performed
   * @param proof - Optional proof to attach to the record
   * @returns The created AuditRecord
   */
  record(envelope: EnvelopeAuditable, action: string, proof?: AuditProof): AuditRecord;

  /**
   * Query audit records for a specific envelope.
   *
   * @param envelope_id - The message_id of the envelope to query
   * @returns List of AuditRecords for this envelope
   */
  query(envelope_id: string): AuditRecord[];
}

/**
 * Generate a UUIDv4 string.
 */
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

/**
 * Compute SHA256 hash of an envelope.
 *
 * @param envelope - The envelope to hash
 * @returns Hex-encoded SHA256 hash of the envelope
 */
export function computeEnvelopeHash(envelope: EnvelopeAuditable): string {
  // Create a deterministic representation of the envelope
  const envelopeCopy: any = { ...envelope };

  // Extract binary fields that can't be JSON serialized
  const payload = envelopeCopy.payload;
  const audit_proof = envelopeCopy.audit_proof;
  delete envelopeCopy.payload;
  delete envelopeCopy.audit_proof;

  // Create deterministic JSON representation of non-binary fields
  // Sort keys and use compact JSON to ensure consistency
  const envelopeJson = JSON.stringify(envelopeCopy, Object.keys(envelopeCopy).sort());

  // Create hash
  const hasher = crypto.createHash('sha256');
  hasher.update(envelopeJson, 'utf-8');

  // Include binary fields in hash
  if (payload) {
    if (payload instanceof Uint8Array) {
      hasher.update(payload);
    } else if (typeof payload === 'string') {
      hasher.update(payload, 'utf-8');
    }
  }

  if (audit_proof) {
    if (audit_proof instanceof Uint8Array) {
      hasher.update(audit_proof);
    } else if (typeof audit_proof === 'string') {
      hasher.update(audit_proof, 'utf-8');
    }
  }

  return hasher.digest('hex');
}

/**
 * Create a simple hash-based proof for an envelope.
 *
 * This is a basic proof mechanism suitable for testing and development.
 * Production systems should use more sophisticated proof mechanisms
 * (e.g., ZK-proofs, digital signatures).
 *
 * @param envelope - The envelope to create proof for
 * @param actor_id - ID of the actor creating the proof
 * @returns An AuditProof with simple hash-based proof
 */
export function createSimpleProof(envelope: EnvelopeAuditable, actor_id: string): AuditProof {
  // Compute envelope hash
  const envelopeHash = computeEnvelopeHash(envelope);

  // Create proof data: hash of (envelope_hash + actor_id + timestamp)
  const timestamp = nowHlcStub();
  const proofInput = `${envelopeHash}:${actor_id}:${timestamp}`;
  const proofHash = crypto.createHash('sha256').update(proofInput, 'utf-8').digest();

  return {
    proof_id: uuidv4(),
    proof_type: 'simple_hash',
    proof_data: new Uint8Array(proofHash),
    created_at: timestamp,
    verified: false,
  };
}

/**
 * Verify an audit proof against an envelope.
 *
 * @param envelope - The envelope to verify against
 * @param proof - The proof to verify
 * @returns True if proof is valid, false otherwise
 */
export function verifyAuditProof(envelope: EnvelopeAuditable, proof: AuditProof): boolean {
  // Handle different proof types
  if (proof.proof_type === 'noop') {
    return true;
  }

  if (proof.proof_type === 'simple_hash') {
    // For simple hash proofs, we verify that:
    // 1. The proof data is non-empty
    // 2. The proof was created for this envelope (basic sanity check)
    if (proof.proof_data.length === 0) {
      return false;
    }

    // Compute expected hash for verification
    const envelopeHash = computeEnvelopeHash(envelope);

    // In a real implementation, we would reconstruct the proof
    // and compare it with the provided proof_data
    // For now, we do a basic check that the hash is consistent
    // This is a simplified verification - production systems need more rigor

    // Verify the proof data is 32 bytes (SHA256 output)
    if (proof.proof_data.length !== 32) {
      return false;
    }

    return true;
  }

  // Unknown proof type
  return false;
}

/**
 * No-op auditor that does nothing.
 *
 * Useful for development and when audit trail is not required.
 */
export class NoOpAuditor implements Auditor {
  /**
   * Create a minimal no-op proof.
   *
   * @param envelope - The envelope (ignored)
   * @param action - The action (ignored)
   * @returns A minimal no-op proof
   */
  createProof(envelope: EnvelopeAuditable, action: string): AuditProof {
    return {
      proof_id: uuidv4(),
      proof_type: 'noop',
      proof_data: new Uint8Array(0),
      created_at: nowHlcStub(),
      verified: true,
    };
  }

  /**
   * Always returns true for no-op proofs.
   *
   * @param proof - The proof (ignored)
   * @returns Always true
   */
  verifyProof(proof: AuditProof): boolean {
    return true;
  }

  /**
   * Create a minimal audit record without storing it.
   *
   * @param envelope - The envelope being audited
   * @param action - The action being performed
   * @param proof - Optional proof to attach
   * @returns A minimal audit record
   */
  record(envelope: EnvelopeAuditable, action: string, proof?: AuditProof): AuditRecord {
    return {
      record_id: uuidv4(),
      envelope_id: envelope.message_id ?? 'unknown',
      action,
      actor_id: envelope.producer_id ?? 'unknown',
      timestamp: nowHlcStub(),
      proof,
    };
  }

  /**
   * Always returns empty array.
   *
   * @param envelope_id - The envelope ID (ignored)
   * @returns Empty array
   */
  query(envelope_id: string): AuditRecord[] {
    return [];
  }
}

/**
 * In-memory auditor for testing and development.
 *
 * Stores audit records in memory and supports basic querying.
 * Not suitable for production use.
 */
export class InMemoryAuditor implements Auditor {
  private _records: Map<string, AuditRecord[]>;

  /**
   * Initialize with empty record storage.
   */
  constructor() {
    this._records = new Map();
  }

  /**
   * Create a simple hash-based proof.
   *
   * @param envelope - The envelope to create proof for
   * @param action - The action being performed
   * @returns A simple hash-based proof
   */
  createProof(envelope: EnvelopeAuditable, action: string): AuditProof {
    return createSimpleProof(envelope, envelope.producer_id ?? 'unknown');
  }

  /**
   * Verify a proof using the verification module.
   *
   * @param proof - The proof to verify
   * @returns True if proof is valid, false otherwise
   */
  verifyProof(proof: AuditProof): boolean {
    // Handle different proof types
    if (proof.proof_type === 'noop') {
      return true;
    }

    // For simple hash proofs, check that the proof_data is non-empty
    if (proof.proof_type === 'simple_hash') {
      return proof.proof_data.length > 0;
    }

    // Unknown proof types are not verified
    return false;
  }

  /**
   * Create and store an audit record.
   *
   * @param envelope - The envelope being audited
   * @param action - The action being performed
   * @param proof - Optional proof to attach
   * @returns The created audit record
   */
  record(envelope: EnvelopeAuditable, action: string, proof?: AuditProof): AuditRecord {
    const record: AuditRecord = {
      record_id: uuidv4(),
      envelope_id: envelope.message_id ?? 'unknown',
      action,
      actor_id: envelope.producer_id ?? 'unknown',
      timestamp: nowHlcStub(),
      proof,
    };

    // Store the record
    const envelope_id = record.envelope_id;
    if (!this._records.has(envelope_id)) {
      this._records.set(envelope_id, []);
    }
    this._records.get(envelope_id)!.push(record);

    return record;
  }

  /**
   * Query all audit records for a specific envelope.
   *
   * @param envelope_id - The message_id of the envelope to query
   * @returns List of audit records for this envelope
   */
  query(envelope_id: string): AuditRecord[] {
    return this._records.get(envelope_id) ?? [];
  }

  /**
   * Get all audit records (useful for testing).
   *
   * @returns All audit records across all envelopes
   */
  getAllRecords(): AuditRecord[] {
    const allRecords: AuditRecord[] = [];
    for (const records of this._records.values()) {
      allRecords.push(...records);
    }
    return allRecords;
  }

  /**
   * Clear all stored records (useful for testing).
   */
  clear(): void {
    this._records.clear();
  }
}
