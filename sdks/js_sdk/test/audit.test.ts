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

import { describe, it, expect, beforeEach } from 'vitest';
import { createHash } from 'node:crypto';
import { buildEnvelope, MessageType, type EnvelopeBuilt } from '../src/internal/envelope.js';

// Define Envelope type alias for the test (since JS SDK uses EnvelopeBuilt)
type Envelope = EnvelopeBuilt;

/**
 * Tests for audit proof extension.
 *
 * These tests verify audit proof creation, verification, and audit trail
 * functionality for the SW4RM protocol.
 *
 * Ported from: sdks/py_sdk/tests/test_audit.py
 */

// Audit types
interface AuditProof {
  proofId: string;
  proofType: 'noop' | 'simple_hash' | string;
  proofData: Uint8Array;
  createdAt: string;
  verified: boolean;
}

interface AuditPolicy {
  policyId: string;
  requireProof: boolean;
  verificationLevel: 'none' | 'basic' | 'strict';
  retentionDays: number;
}

interface AuditRecord {
  recordId: string;
  envelopeId: string;
  action: string;
  actorId: string;
  timestamp: string;
  proof?: AuditProof;
}

// Auditor interface
interface Auditor {
  createProof(env: Envelope, action: string): AuditProof;
  verifyProof(proof: AuditProof): boolean;
  record(env: Envelope, action: string, proof: AuditProof | null): AuditRecord;
  query(envelopeId: string): AuditRecord[];
}

// Utility functions
function computeEnvelopeHash(env: Envelope): string {
  const data = JSON.stringify({
    message_id: env.message_id,
    producer_id: env.producer_id,
    message_type: env.message_type,
    payload: env.payload ? Array.from(env.payload) : [],
  });
  return createHash('sha256').update(data).digest('hex');
}

function createSimpleProof(env: Envelope, actorId: string): AuditProof {
  const timestamp = Date.now().toString();
  const proofInput = `${computeEnvelopeHash(env)}:${actorId}:${timestamp}`;
  const proofData = createHash('sha256').update(proofInput).digest();

  return {
    proofId: `proof-${Date.now()}-${Math.random().toString(36).substring(2, 9)}`,
    proofType: 'simple_hash',
    proofData: new Uint8Array(proofData),
    createdAt: timestamp,
    verified: false,
  };
}

function verifyAuditProof(env: Envelope, proof: AuditProof): boolean {
  if (proof.proofType === 'noop') {
    return true;
  }
  if (proof.proofType === 'simple_hash') {
    // Simple hash proofs just need to have correct size (SHA256 = 32 bytes)
    return proof.proofData.length === 32;
  }
  return false;
}

// NoOp Auditor implementation
class NoOpAuditor implements Auditor {
  createProof(env: Envelope, _action: string): AuditProof {
    return {
      proofId: `noop-${Date.now()}`,
      proofType: 'noop',
      proofData: new Uint8Array(),
      createdAt: Date.now().toString(),
      verified: true,
    };
  }

  verifyProof(_proof: AuditProof): boolean {
    return true;
  }

  record(env: Envelope, action: string, proof: AuditProof | null): AuditRecord {
    return {
      recordId: `record-${Date.now()}`,
      envelopeId: env.message_id,
      action,
      actorId: env.producer_id,
      timestamp: Date.now().toString(),
      proof: proof ?? undefined,
    };
  }

  query(_envelopeId: string): AuditRecord[] {
    return [];
  }
}

// InMemory Auditor implementation
class InMemoryAuditor implements Auditor {
  private records: Map<string, AuditRecord[]> = new Map();

  createProof(env: Envelope, action: string): AuditProof {
    return createSimpleProof(env, env.producer_id);
  }

  verifyProof(proof: AuditProof): boolean {
    if (proof.proofType === 'noop') return true;
    if (proof.proofType === 'simple_hash') {
      return proof.proofData.length === 32;
    }
    return false;
  }

  record(env: Envelope, action: string, proof: AuditProof | null): AuditRecord {
    const record: AuditRecord = {
      recordId: `record-${Date.now()}-${Math.random().toString(36).substring(2, 9)}`,
      envelopeId: env.message_id,
      action,
      actorId: env.producer_id,
      timestamp: Date.now().toString(),
      proof: proof ?? undefined,
    };

    const existing = this.records.get(env.message_id) ?? [];
    existing.push(record);
    this.records.set(env.message_id, existing);

    return record;
  }

  query(envelopeId: string): AuditRecord[] {
    return this.records.get(envelopeId) ?? [];
  }

  getAllRecords(): AuditRecord[] {
    const all: AuditRecord[] = [];
    for (const records of this.records.values()) {
      all.push(...records);
    }
    return all;
  }

  clear(): void {
    this.records.clear();
  }
}

describe('Audit', () => {
  describe('AuditTypes', () => {
    it('should create AuditProof instance', () => {
      const proof: AuditProof = {
        proofId: 'proof-123',
        proofType: 'simple_hash',
        proofData: new Uint8Array([1, 2, 3]),
        createdAt: '1234567890',
        verified: false,
      };

      expect(proof.proofId).toBe('proof-123');
      expect(proof.proofType).toBe('simple_hash');
      expect(proof.proofData).toBeInstanceOf(Uint8Array);
      expect(proof.createdAt).toBe('1234567890');
      expect(proof.verified).toBe(false);
    });

    it('should create AuditPolicy instance', () => {
      const policy: AuditPolicy = {
        policyId: 'policy-456',
        requireProof: true,
        verificationLevel: 'strict',
        retentionDays: 90,
      };

      expect(policy.policyId).toBe('policy-456');
      expect(policy.requireProof).toBe(true);
      expect(policy.verificationLevel).toBe('strict');
      expect(policy.retentionDays).toBe(90);
    });

    it('should create AuditRecord instance', () => {
      const proof: AuditProof = {
        proofId: 'proof-123',
        proofType: 'simple_hash',
        proofData: new Uint8Array([1, 2, 3]),
        createdAt: '1234567890',
        verified: false,
      };

      const record: AuditRecord = {
        recordId: 'record-789',
        envelopeId: 'env-123',
        action: 'send',
        actorId: 'agent-1',
        timestamp: '1234567890',
        proof,
      };

      expect(record.recordId).toBe('record-789');
      expect(record.envelopeId).toBe('env-123');
      expect(record.action).toBe('send');
      expect(record.actorId).toBe('agent-1');
      expect(record.proof).toBe(proof);
    });

    it('should create AuditRecord without proof', () => {
      const record: AuditRecord = {
        recordId: 'record-789',
        envelopeId: 'env-123',
        action: 'send',
        actorId: 'agent-1',
        timestamp: '1234567890',
      };

      expect(record.proof).toBeUndefined();
    });
  });

  describe('Verification Functions', () => {
    it('should compute deterministic envelope hash', () => {
      const env = buildEnvelope({
        producer_id: 'agent-1',
        message_type: MessageType.DATA,
        payload: new TextEncoder().encode('test payload'),
      });

      const hash1 = computeEnvelopeHash(env);
      const hash2 = computeEnvelopeHash(env);

      expect(hash1).toBe(hash2);
      expect(hash1).toHaveLength(64); // SHA256 hex digest
    });

    it('should compute different hashes for different envelopes', () => {
      const env1 = buildEnvelope({
        producer_id: 'agent-1',
        message_type: MessageType.DATA,
        payload: new TextEncoder().encode('payload1'),
      });

      const env2 = buildEnvelope({
        producer_id: 'agent-2',
        message_type: MessageType.DATA,
        payload: new TextEncoder().encode('payload2'),
      });

      const hash1 = computeEnvelopeHash(env1);
      const hash2 = computeEnvelopeHash(env2);

      expect(hash1).not.toBe(hash2);
    });

    it('should create simple proof', () => {
      const env = buildEnvelope({
        producer_id: 'agent-1',
        message_type: MessageType.DATA,
        payload: new TextEncoder().encode('test'),
      });

      const proof = createSimpleProof(env, 'agent-1');

      expect(proof.proofType).toBe('simple_hash');
      expect(proof.proofData.length).toBe(32); // SHA256 output
      expect(proof.verified).toBe(false);
      expect(proof.proofId).toBeTruthy();
      expect(proof.createdAt).toBeTruthy();
    });

    it('should verify simple hash proof', () => {
      const env = buildEnvelope({
        producer_id: 'agent-1',
        message_type: MessageType.DATA,
        payload: new TextEncoder().encode('test'),
      });

      const proof = createSimpleProof(env, 'agent-1');
      expect(verifyAuditProof(env, proof)).toBe(true);
    });

    it('should verify noop proof', () => {
      const env = buildEnvelope({
        producer_id: 'agent-1',
        message_type: MessageType.DATA,
      });

      const proof: AuditProof = {
        proofId: 'test-id',
        proofType: 'noop',
        proofData: new Uint8Array(),
        createdAt: '1234567890',
        verified: false,
      };

      expect(verifyAuditProof(env, proof)).toBe(true);
    });

    it('should reject invalid simple hash proof', () => {
      const env = buildEnvelope({
        producer_id: 'agent-1',
        message_type: MessageType.DATA,
      });

      const proof: AuditProof = {
        proofId: 'test-id',
        proofType: 'simple_hash',
        proofData: new Uint8Array([1, 2, 3]), // Wrong size
        createdAt: '1234567890',
        verified: false,
      };

      expect(verifyAuditProof(env, proof)).toBe(false);
    });

    it('should reject unknown proof type', () => {
      const env = buildEnvelope({
        producer_id: 'agent-1',
        message_type: MessageType.DATA,
      });

      const proof: AuditProof = {
        proofId: 'test-id',
        proofType: 'unknown_type',
        proofData: new Uint8Array([1, 2, 3]),
        createdAt: '1234567890',
        verified: false,
      };

      expect(verifyAuditProof(env, proof)).toBe(false);
    });
  });

  describe('NoOpAuditor', () => {
    let auditor: NoOpAuditor;

    beforeEach(() => {
      auditor = new NoOpAuditor();
    });

    it('should create minimal proof', () => {
      const env = buildEnvelope({
        producer_id: 'agent-1',
        message_type: MessageType.DATA,
      });

      const proof = auditor.createProof(env, 'send');

      expect(proof.proofType).toBe('noop');
      expect(proof.proofData.length).toBe(0);
      expect(proof.verified).toBe(true);
    });

    it('should always verify proofs', () => {
      const proof: AuditProof = {
        proofId: 'test',
        proofType: 'anything',
        proofData: new Uint8Array([1, 2, 3]),
        createdAt: '123',
        verified: false,
      };

      expect(auditor.verifyProof(proof)).toBe(true);
    });

    it('should create audit record', () => {
      const env = buildEnvelope({
        producer_id: 'agent-1',
        message_type: MessageType.DATA,
      });

      const record = auditor.record(env, 'send', null);

      expect(record.envelopeId).toBe(env.message_id);
      expect(record.action).toBe('send');
      expect(record.actorId).toBe('agent-1');
      expect(record.proof).toBeUndefined();
    });

    it('should create record with proof', () => {
      const env = buildEnvelope({
        producer_id: 'agent-1',
        message_type: MessageType.DATA,
      });

      const proof = auditor.createProof(env, 'send');
      const record = auditor.record(env, 'send', proof);

      expect(record.proof).toBe(proof);
    });

    it('should always return empty query', () => {
      expect(auditor.query('any-id')).toEqual([]);
    });
  });

  describe('InMemoryAuditor', () => {
    let auditor: InMemoryAuditor;

    beforeEach(() => {
      auditor = new InMemoryAuditor();
    });

    it('should create simple hash proof', () => {
      const env = buildEnvelope({
        producer_id: 'agent-1',
        message_type: MessageType.DATA,
      });

      const proof = auditor.createProof(env, 'send');

      expect(proof.proofType).toBe('simple_hash');
      expect(proof.proofData.length).toBe(32);
      expect(proof.verified).toBe(false);
    });

    it('should verify simple hash proofs', () => {
      const env = buildEnvelope({
        producer_id: 'agent-1',
        message_type: MessageType.DATA,
      });

      const proof = auditor.createProof(env, 'send');
      expect(auditor.verifyProof(proof)).toBe(true);
    });

    it('should verify noop proofs', () => {
      const proof: AuditProof = {
        proofId: 'test',
        proofType: 'noop',
        proofData: new Uint8Array(),
        createdAt: '123',
        verified: false,
      };

      expect(auditor.verifyProof(proof)).toBe(true);
    });

    it('should reject invalid proofs', () => {
      const proof: AuditProof = {
        proofId: 'test',
        proofType: 'unknown',
        proofData: new Uint8Array([1, 2, 3]),
        createdAt: '123',
        verified: false,
      };

      expect(auditor.verifyProof(proof)).toBe(false);
    });

    it('should store audit records', () => {
      const env = buildEnvelope({
        producer_id: 'agent-1',
        message_type: MessageType.DATA,
      });

      const record = auditor.record(env, 'send', null);

      expect(record.envelopeId).toBe(env.message_id);
      expect(record.action).toBe('send');

      const records = auditor.query(env.message_id);
      expect(records).toHaveLength(1);
      expect(records[0]).toEqual(record);
    });

    it('should track multiple actions for same envelope', () => {
      const env = buildEnvelope({
        producer_id: 'agent-1',
        message_type: MessageType.DATA,
      });

      auditor.record(env, 'send', null);
      auditor.record(env, 'receive', null);
      auditor.record(env, 'process', null);

      const records = auditor.query(env.message_id);
      expect(records).toHaveLength(3);
      expect(records[0].action).toBe('send');
      expect(records[1].action).toBe('receive');
      expect(records[2].action).toBe('process');
    });

    it('should return empty array for non-existent envelope', () => {
      const records = auditor.query('nonexistent-id');
      expect(records).toEqual([]);
    });

    it('should get all records across envelopes', () => {
      const env1 = buildEnvelope({ producer_id: 'agent-1', message_type: MessageType.DATA });
      const env2 = buildEnvelope({ producer_id: 'agent-2', message_type: MessageType.DATA });

      auditor.record(env1, 'send', null);
      auditor.record(env1, 'receive', null);
      auditor.record(env2, 'send', null);

      const allRecords = auditor.getAllRecords();
      expect(allRecords).toHaveLength(3);
    });

    it('should clear all records', () => {
      const env = buildEnvelope({ producer_id: 'agent-1', message_type: MessageType.DATA });

      auditor.record(env, 'send', null);
      expect(auditor.getAllRecords()).toHaveLength(1);

      auditor.clear();
      expect(auditor.getAllRecords()).toHaveLength(0);
      expect(auditor.query(env.message_id)).toEqual([]);
    });
  });

  describe('Envelope Integration', () => {
    // Note: The JS SDK envelope does not currently have audit_proof and audit_policy_id fields.
    // These tests verify that the auditor can work with envelopes by storing proofs externally.

    it('should work with envelope message_id as key', () => {
      const env = buildEnvelope({
        producer_id: 'agent-1',
        message_type: MessageType.DATA,
        payload: new TextEncoder().encode('test'),
      });

      // Envelope has required fields for auditing
      expect(env.message_id).toBeTruthy();
      expect(env.producer_id).toBe('agent-1');
    });

    it('should compute hash from envelope fields', () => {
      const env = buildEnvelope({
        producer_id: 'agent-1',
        message_type: MessageType.DATA,
        payload: new TextEncoder().encode('test'),
      });

      const hash = computeEnvelopeHash(env);
      expect(hash).toHaveLength(64); // SHA256 hex
    });

    it('should work with envelopes without payload', () => {
      const env = buildEnvelope({
        producer_id: 'agent-1',
        message_type: MessageType.DATA,
      });

      // Should not throw
      const hash = computeEnvelopeHash(env);
      expect(hash).toHaveLength(64);
    });

    it('should create proof from envelope', () => {
      const env = buildEnvelope({
        producer_id: 'agent-1',
        message_type: MessageType.DATA,
      });

      const proof = createSimpleProof(env, 'agent-1');
      expect(proof.proofType).toBe('simple_hash');
      expect(proof.proofData.length).toBe(32);
    });
  });

  describe('Audit Workflow', () => {
    it('should support full audit workflow: create, record, query', () => {
      const auditor = new InMemoryAuditor();

      const env = buildEnvelope({
        producer_id: 'agent-1',
        message_type: MessageType.DATA,
        payload: new TextEncoder().encode('test payload'),
      });

      // Create proof
      const proof = auditor.createProof(env, 'send');
      expect(auditor.verifyProof(proof)).toBe(true);

      // Record action with proof
      const record = auditor.record(env, 'send', proof);
      expect(record.proof).toBe(proof);

      // Query records
      const records = auditor.query(env.message_id);
      expect(records).toHaveLength(1);
      expect(records[0].proof).toBe(proof);
    });

    it('should support audit workflow with external proof storage', () => {
      const auditor = new InMemoryAuditor();
      // External proof storage (simulating what would happen with audit_proof in envelope)
      const proofStorage = new Map<string, { proofData: Uint8Array; policyId: string }>();

      const env = buildEnvelope({
        producer_id: 'agent-1',
        message_type: MessageType.DATA,
        payload: new TextEncoder().encode('test'),
      });

      const proof = auditor.createProof(env, 'send');

      // Store proof externally (in practice, this would be in the envelope)
      proofStorage.set(env.message_id, { proofData: proof.proofData, policyId: 'policy-1' });

      // Record
      auditor.record(env, 'send', proof);

      // Verify stored proof data
      const storedProof = proofStorage.get(env.message_id);
      expect(storedProof?.proofData).toEqual(proof.proofData);
      expect(storedProof?.policyId).toBe('policy-1');

      // Query
      const records = auditor.query(env.message_id);
      expect(records).toHaveLength(1);
    });

    it('should support audit trail across multiple agents', () => {
      const auditor = new InMemoryAuditor();

      // Agent 1 sends
      const env = buildEnvelope({
        producer_id: 'agent-1',
        message_type: MessageType.DATA,
        payload: new TextEncoder().encode('message content'),
      });

      const proof1 = auditor.createProof(env, 'send');
      auditor.record(env, 'send', proof1);

      // Agent 2 receives (use same envelope to simulate forwarding)
      const proof2 = auditor.createProof(env, 'receive');
      auditor.record(env, 'receive', proof2);

      // Agent 2 processes
      const proof3 = auditor.createProof(env, 'process');
      auditor.record(env, 'process', proof3);

      // Verify audit trail
      const records = auditor.query(env.message_id);
      expect(records).toHaveLength(3);
      expect(records[0].action).toBe('send');
      expect(records[1].action).toBe('receive');
      expect(records[2].action).toBe('process');

      // Each has a proof
      for (const record of records) {
        expect(record.proof).toBeDefined();
        expect(auditor.verifyProof(record.proof!)).toBe(true);
      }
    });
  });
});
