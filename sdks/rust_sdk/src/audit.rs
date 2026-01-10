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

//! Audit proof extension for SW4RM protocol.
//!
//! This module provides audit trail capabilities with optional proof generation
//! and verification, inspired by ZK-MCP research.

use sha2::{Digest, Sha256};
use std::collections::HashMap;
use uuid::Uuid;

use crate::envelope::EnvelopeData;

/// Represents a cryptographic or logical proof for an audit event.
#[derive(Debug, Clone, PartialEq)]
pub struct AuditProof {
    /// Unique identifier for this proof
    pub proof_id: String,
    /// Type of proof (e.g., "simple_hash", "zk_proof", "signature", "noop")
    pub proof_type: String,
    /// The actual proof data as bytes
    pub proof_data: Vec<u8>,
    /// Timestamp when the proof was created (HLC or unix ms)
    pub created_at: String,
    /// Whether this proof has been verified
    pub verified: bool,
}

impl AuditProof {
    /// Create a new AuditProof
    pub fn new(
        proof_id: String,
        proof_type: String,
        proof_data: Vec<u8>,
        created_at: String,
    ) -> Self {
        Self {
            proof_id,
            proof_type,
            proof_data,
            created_at,
            verified: false,
        }
    }

    /// Create a no-op proof (always verified)
    pub fn noop() -> Self {
        Self {
            proof_id: Uuid::new_v4().to_string(),
            proof_type: "noop".to_string(),
            proof_data: Vec::new(),
            created_at: chrono::Utc::now().timestamp_millis().to_string(),
            verified: true,
        }
    }
}

/// Defines audit requirements for envelope processing.
#[derive(Debug, Clone, PartialEq)]
pub struct AuditPolicy {
    /// Unique identifier for this policy
    pub policy_id: String,
    /// Whether proof is required for this policy
    pub require_proof: bool,
    /// Level of verification required (e.g., "none", "basic", "strict")
    pub verification_level: String,
    /// How many days to retain audit records
    pub retention_days: i32,
}

impl Default for AuditPolicy {
    fn default() -> Self {
        Self {
            policy_id: String::new(),
            require_proof: false,
            verification_level: "none".to_string(),
            retention_days: 90,
        }
    }
}

/// Represents a complete audit record for an envelope action.
#[derive(Debug, Clone, PartialEq)]
pub struct AuditRecord {
    /// Unique identifier for this audit record
    pub record_id: String,
    /// The message_id of the envelope being audited
    pub envelope_id: String,
    /// The action performed (e.g., "send", "receive", "process")
    pub action: String,
    /// ID of the agent/component that performed the action
    pub actor_id: String,
    /// When the action occurred (HLC or unix ms)
    pub timestamp: String,
    /// Optional proof associated with this action
    pub proof: Option<AuditProof>,
}

impl AuditRecord {
    /// Create a new AuditRecord
    pub fn new(
        envelope_id: String,
        action: String,
        actor_id: String,
        proof: Option<AuditProof>,
    ) -> Self {
        Self {
            record_id: Uuid::new_v4().to_string(),
            envelope_id,
            action,
            actor_id,
            timestamp: chrono::Utc::now().timestamp_millis().to_string(),
            proof,
        }
    }
}

/// Trait for audit implementations
pub trait Auditor: Send + Sync {
    /// Create a proof for an envelope action
    fn create_proof(&self, envelope: &EnvelopeData, action: &str) -> AuditProof;

    /// Verify a proof
    fn verify_proof(&self, proof: &AuditProof) -> bool;

    /// Record an audit event
    fn record(
        &mut self,
        envelope: &EnvelopeData,
        action: &str,
        proof: Option<AuditProof>,
    ) -> AuditRecord;

    /// Query audit records for an envelope
    fn query(&self, envelope_id: &str) -> Vec<AuditRecord>;
}

/// No-op auditor implementation (always succeeds, doesn't store)
#[derive(Debug, Default)]
pub struct NoOpAuditor;

impl NoOpAuditor {
    pub fn new() -> Self {
        Self
    }
}

impl Auditor for NoOpAuditor {
    fn create_proof(&self, _envelope: &EnvelopeData, _action: &str) -> AuditProof {
        AuditProof::noop()
    }

    fn verify_proof(&self, _proof: &AuditProof) -> bool {
        true
    }

    fn record(
        &mut self,
        envelope: &EnvelopeData,
        action: &str,
        proof: Option<AuditProof>,
    ) -> AuditRecord {
        AuditRecord::new(
            envelope.message_id.clone(),
            action.to_string(),
            envelope.producer_id.clone(),
            proof,
        )
    }

    fn query(&self, _envelope_id: &str) -> Vec<AuditRecord> {
        Vec::new()
    }
}

/// In-memory auditor implementation with simple hash proofs
#[derive(Debug, Default)]
pub struct InMemoryAuditor {
    records: HashMap<String, Vec<AuditRecord>>,
}

impl InMemoryAuditor {
    pub fn new() -> Self {
        Self {
            records: HashMap::new(),
        }
    }

    /// Get all records across all envelopes
    pub fn get_all_records(&self) -> Vec<AuditRecord> {
        self.records
            .values()
            .flatten()
            .cloned()
            .collect()
    }

    /// Clear all audit records
    pub fn clear(&mut self) {
        self.records.clear();
    }
}

impl Auditor for InMemoryAuditor {
    fn create_proof(&self, envelope: &EnvelopeData, _action: &str) -> AuditProof {
        create_simple_proof(envelope)
    }

    fn verify_proof(&self, proof: &AuditProof) -> bool {
        verify_audit_proof(proof)
    }

    fn record(
        &mut self,
        envelope: &EnvelopeData,
        action: &str,
        proof: Option<AuditProof>,
    ) -> AuditRecord {
        let record = AuditRecord::new(
            envelope.message_id.clone(),
            action.to_string(),
            envelope.producer_id.clone(),
            proof,
        );

        self.records
            .entry(envelope.message_id.clone())
            .or_default()
            .push(record.clone());

        record
    }

    fn query(&self, envelope_id: &str) -> Vec<AuditRecord> {
        self.records
            .get(envelope_id)
            .cloned()
            .unwrap_or_default()
    }
}

/// Compute a deterministic hash of an envelope
pub fn compute_envelope_hash(envelope: &EnvelopeData) -> String {
    let mut hasher = Sha256::new();
    hasher.update(envelope.message_id.as_bytes());
    hasher.update(envelope.producer_id.as_bytes());
    hasher.update(&envelope.payload);
    hasher.update(envelope.message_type.to_le_bytes());
    let result = hasher.finalize();
    hex::encode(result)
}

/// Create a simple hash-based proof for an envelope
pub fn create_simple_proof(envelope: &EnvelopeData) -> AuditProof {
    let hash = compute_envelope_hash(envelope);
    let proof_data = hex::decode(&hash).unwrap_or_default();

    AuditProof {
        proof_id: Uuid::new_v4().to_string(),
        proof_type: "simple_hash".to_string(),
        proof_data,
        created_at: chrono::Utc::now().timestamp_millis().to_string(),
        verified: false,
    }
}

/// Verify an audit proof
pub fn verify_audit_proof(proof: &AuditProof) -> bool {
    match proof.proof_type.as_str() {
        "noop" => true,
        "simple_hash" => proof.proof_data.len() == 32, // SHA256 output is 32 bytes
        _ => false,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::constants::message_type;
    use crate::envelope::EnvelopeBuilder;

    /// Helper function to create a test envelope
    fn create_test_envelope(producer_id: &str) -> EnvelopeData {
        EnvelopeBuilder::new(producer_id.to_string(), message_type::DATA).build()
    }

    /// Helper function to create a test envelope with payload
    fn create_test_envelope_with_payload(producer_id: &str, payload: Vec<u8>) -> EnvelopeData {
        EnvelopeBuilder::new(producer_id.to_string(), message_type::DATA)
            .with_payload(payload)
            .build()
    }

    /// Test AuditProof creation
    #[test]
    fn test_audit_proof_creation() {
        let proof = AuditProof::new(
            "proof-123".to_string(),
            "simple_hash".to_string(),
            b"test_proof_data".to_vec(),
            "1234567890".to_string(),
        );

        assert_eq!(proof.proof_id, "proof-123");
        assert_eq!(proof.proof_type, "simple_hash");
        assert_eq!(proof.proof_data, b"test_proof_data");
        assert_eq!(proof.created_at, "1234567890");
        assert!(!proof.verified);
    }

    /// Test AuditProof noop creation
    #[test]
    fn test_audit_proof_noop() {
        let proof = AuditProof::noop();

        assert_eq!(proof.proof_type, "noop");
        assert!(proof.proof_data.is_empty());
        assert!(proof.verified);
        assert!(!proof.proof_id.is_empty());
    }

    /// Test AuditPolicy creation
    #[test]
    fn test_audit_policy_creation() {
        let policy = AuditPolicy {
            policy_id: "policy-456".to_string(),
            require_proof: true,
            verification_level: "strict".to_string(),
            retention_days: 90,
        };

        assert_eq!(policy.policy_id, "policy-456");
        assert!(policy.require_proof);
        assert_eq!(policy.verification_level, "strict");
        assert_eq!(policy.retention_days, 90);
    }

    /// Test AuditPolicy default values
    #[test]
    fn test_audit_policy_default() {
        let policy = AuditPolicy::default();

        assert!(policy.policy_id.is_empty());
        assert!(!policy.require_proof);
        assert_eq!(policy.verification_level, "none");
        assert_eq!(policy.retention_days, 90);
    }

    /// Test AuditRecord creation
    #[test]
    fn test_audit_record_creation() {
        let proof = AuditProof::noop();
        let record = AuditRecord::new(
            "env-123".to_string(),
            "send".to_string(),
            "agent-1".to_string(),
            Some(proof.clone()),
        );

        assert!(!record.record_id.is_empty());
        assert_eq!(record.envelope_id, "env-123");
        assert_eq!(record.action, "send");
        assert_eq!(record.actor_id, "agent-1");
        assert!(!record.timestamp.is_empty());
        assert!(record.proof.is_some());
    }

    /// Test AuditRecord without proof
    #[test]
    fn test_audit_record_without_proof() {
        let record = AuditRecord::new(
            "env-123".to_string(),
            "send".to_string(),
            "agent-1".to_string(),
            None,
        );

        assert!(record.proof.is_none());
    }

    /// Test compute_envelope_hash is deterministic
    #[test]
    fn test_compute_envelope_hash_deterministic() {
        let envelope = create_test_envelope_with_payload("agent-1", b"test payload".to_vec());

        let hash1 = compute_envelope_hash(&envelope);
        let hash2 = compute_envelope_hash(&envelope);

        assert_eq!(hash1, hash2);
        assert_eq!(hash1.len(), 64); // SHA256 hex digest
    }

    /// Test compute_envelope_hash different for different envelopes
    #[test]
    fn test_compute_envelope_hash_different() {
        let envelope1 = create_test_envelope_with_payload("agent-1", b"payload1".to_vec());
        let envelope2 = create_test_envelope_with_payload("agent-2", b"payload2".to_vec());

        let hash1 = compute_envelope_hash(&envelope1);
        let hash2 = compute_envelope_hash(&envelope2);

        assert_ne!(hash1, hash2);
    }

    /// Test create_simple_proof
    #[test]
    fn test_create_simple_proof() {
        let envelope = create_test_envelope_with_payload("agent-1", b"test".to_vec());

        let proof = create_simple_proof(&envelope);

        assert_eq!(proof.proof_type, "simple_hash");
        assert_eq!(proof.proof_data.len(), 32); // SHA256 output
        assert!(!proof.verified);
        assert!(!proof.proof_id.is_empty());
        assert!(!proof.created_at.is_empty());
    }

    /// Test verify_audit_proof simple_hash
    #[test]
    fn test_verify_audit_proof_simple_hash() {
        let envelope = create_test_envelope_with_payload("agent-1", b"test".to_vec());

        let proof = create_simple_proof(&envelope);

        assert!(verify_audit_proof(&proof));
    }

    /// Test verify_audit_proof noop
    #[test]
    fn test_verify_audit_proof_noop() {
        let proof = AuditProof::noop();
        assert!(verify_audit_proof(&proof));
    }

    /// Test verify_audit_proof invalid simple_hash
    #[test]
    fn test_verify_audit_proof_invalid_simple_hash() {
        let proof = AuditProof::new(
            "test-id".to_string(),
            "simple_hash".to_string(),
            b"invalid".to_vec(), // Wrong size
            "1234567890".to_string(),
        );

        assert!(!verify_audit_proof(&proof));
    }

    /// Test verify_audit_proof unknown type
    #[test]
    fn test_verify_audit_proof_unknown_type() {
        let proof = AuditProof::new(
            "test-id".to_string(),
            "unknown_type".to_string(),
            b"some data".to_vec(),
            "1234567890".to_string(),
        );

        assert!(!verify_audit_proof(&proof));
    }

    /// Test NoOpAuditor create_proof
    #[test]
    fn test_noop_auditor_create_proof() {
        let auditor = NoOpAuditor::new();
        let envelope = create_test_envelope("agent-1");

        let proof = auditor.create_proof(&envelope, "send");

        assert_eq!(proof.proof_type, "noop");
        assert!(proof.proof_data.is_empty());
        assert!(proof.verified);
    }

    /// Test NoOpAuditor verify_proof always true
    #[test]
    fn test_noop_auditor_verify_proof() {
        let auditor = NoOpAuditor::new();
        let proof = AuditProof::new(
            "test".to_string(),
            "anything".to_string(),
            b"anything".to_vec(),
            "123".to_string(),
        );

        assert!(auditor.verify_proof(&proof));
    }

    /// Test NoOpAuditor record creates record
    #[test]
    fn test_noop_auditor_record() {
        let mut auditor = NoOpAuditor::new();
        let envelope = create_test_envelope("agent-1");

        let record = auditor.record(&envelope, "send", None);

        assert_eq!(record.envelope_id, envelope.message_id);
        assert_eq!(record.action, "send");
        assert_eq!(record.actor_id, "agent-1");
        assert!(record.proof.is_none());
    }

    /// Test NoOpAuditor query always empty
    #[test]
    fn test_noop_auditor_query() {
        let auditor = NoOpAuditor::new();
        assert!(auditor.query("any-id").is_empty());
    }

    /// Test InMemoryAuditor create_proof
    #[test]
    fn test_inmemory_auditor_create_proof() {
        let auditor = InMemoryAuditor::new();
        let envelope = create_test_envelope("agent-1");

        let proof = auditor.create_proof(&envelope, "send");

        assert_eq!(proof.proof_type, "simple_hash");
        assert_eq!(proof.proof_data.len(), 32);
        assert!(!proof.verified);
    }

    /// Test InMemoryAuditor verify_proof simple_hash
    #[test]
    fn test_inmemory_auditor_verify_proof() {
        let auditor = InMemoryAuditor::new();
        let envelope = create_test_envelope("agent-1");

        let proof = auditor.create_proof(&envelope, "send");
        assert!(auditor.verify_proof(&proof));
    }

    /// Test InMemoryAuditor verify_proof noop
    #[test]
    fn test_inmemory_auditor_verify_noop() {
        let auditor = InMemoryAuditor::new();
        let proof = AuditProof::noop();
        assert!(auditor.verify_proof(&proof));
    }

    /// Test InMemoryAuditor verify_proof invalid
    #[test]
    fn test_inmemory_auditor_verify_invalid() {
        let auditor = InMemoryAuditor::new();
        let proof = AuditProof::new(
            "test".to_string(),
            "unknown".to_string(),
            b"data".to_vec(),
            "123".to_string(),
        );

        assert!(!auditor.verify_proof(&proof));
    }

    /// Test InMemoryAuditor record stores record
    #[test]
    fn test_inmemory_auditor_record() {
        let mut auditor = InMemoryAuditor::new();
        let envelope = create_test_envelope("agent-1");

        let record = auditor.record(&envelope, "send", None);

        assert_eq!(record.envelope_id, envelope.message_id);
        assert_eq!(record.action, "send");

        // Query should return the record
        let records = auditor.query(&envelope.message_id);
        assert_eq!(records.len(), 1);
        assert_eq!(records[0], record);
    }

    /// Test InMemoryAuditor record multiple actions
    #[test]
    fn test_inmemory_auditor_multiple_actions() {
        let mut auditor = InMemoryAuditor::new();
        let envelope = create_test_envelope("agent-1");

        auditor.record(&envelope, "send", None);
        auditor.record(&envelope, "receive", None);
        auditor.record(&envelope, "process", None);

        let records = auditor.query(&envelope.message_id);
        assert_eq!(records.len(), 3);
        assert_eq!(records[0].action, "send");
        assert_eq!(records[1].action, "receive");
        assert_eq!(records[2].action, "process");
    }

    /// Test InMemoryAuditor query nonexistent envelope
    #[test]
    fn test_inmemory_auditor_query_nonexistent() {
        let auditor = InMemoryAuditor::new();
        let records = auditor.query("nonexistent-id");
        assert!(records.is_empty());
    }

    /// Test InMemoryAuditor get_all_records
    #[test]
    fn test_inmemory_auditor_get_all_records() {
        let mut auditor = InMemoryAuditor::new();
        let envelope1 = create_test_envelope("agent-1");
        let envelope2 = create_test_envelope("agent-2");

        auditor.record(&envelope1, "send", None);
        auditor.record(&envelope1, "receive", None);
        auditor.record(&envelope2, "send", None);

        let all_records = auditor.get_all_records();
        assert_eq!(all_records.len(), 3);
    }

    /// Test InMemoryAuditor clear
    #[test]
    fn test_inmemory_auditor_clear() {
        let mut auditor = InMemoryAuditor::new();
        let envelope = create_test_envelope("agent-1");

        auditor.record(&envelope, "send", None);
        assert_eq!(auditor.get_all_records().len(), 1);

        auditor.clear();
        assert!(auditor.get_all_records().is_empty());
        assert!(auditor.query(&envelope.message_id).is_empty());
    }

    /// Test full audit workflow
    #[test]
    fn test_full_audit_workflow() {
        let mut auditor = InMemoryAuditor::new();

        // Build envelope
        let envelope = create_test_envelope_with_payload("agent-1", b"test payload".to_vec());

        // Create proof
        let proof = auditor.create_proof(&envelope, "send");
        assert!(auditor.verify_proof(&proof));

        // Record action with proof
        let record = auditor.record(&envelope, "send", Some(proof.clone()));
        assert!(record.proof.is_some());

        // Query records
        let records = auditor.query(&envelope.message_id);
        assert_eq!(records.len(), 1);
        assert!(records[0].proof.is_some());
    }

    /// Test audit trail across multiple agents
    #[test]
    fn test_audit_trail_multiple_agents() {
        let mut auditor = InMemoryAuditor::new();

        // Agent 1 sends
        let envelope = create_test_envelope("agent-1");

        let proof1 = auditor.create_proof(&envelope, "send");
        auditor.record(&envelope, "send", Some(proof1));

        // Agent 2 receives
        let proof2 = auditor.create_proof(&envelope, "receive");
        auditor.record(&envelope, "receive", Some(proof2));

        // Agent 2 processes
        let proof3 = auditor.create_proof(&envelope, "process");
        auditor.record(&envelope, "process", Some(proof3));

        // Verify audit trail
        let records = auditor.query(&envelope.message_id);
        assert_eq!(records.len(), 3);
        assert_eq!(records[0].action, "send");
        assert_eq!(records[1].action, "receive");
        assert_eq!(records[2].action, "process");

        // Each has a proof
        for record in &records {
            assert!(record.proof.is_some());
            assert!(auditor.verify_proof(record.proof.as_ref().unwrap()));
        }
    }

    /// Test AuditProof clone
    #[test]
    fn test_audit_proof_clone() {
        let proof = AuditProof::new(
            "proof-1".to_string(),
            "simple_hash".to_string(),
            b"data".to_vec(),
            "123".to_string(),
        );

        let cloned = proof.clone();
        assert_eq!(proof, cloned);
    }

    /// Test AuditPolicy clone
    #[test]
    fn test_audit_policy_clone() {
        let policy = AuditPolicy {
            policy_id: "policy-1".to_string(),
            require_proof: true,
            verification_level: "strict".to_string(),
            retention_days: 30,
        };

        let cloned = policy.clone();
        assert_eq!(policy, cloned);
    }

    /// Test AuditRecord clone
    #[test]
    fn test_audit_record_clone() {
        let record = AuditRecord::new(
            "env-1".to_string(),
            "send".to_string(),
            "agent-1".to_string(),
            None,
        );

        let cloned = record.clone();
        assert_eq!(record.envelope_id, cloned.envelope_id);
        assert_eq!(record.action, cloned.action);
        assert_eq!(record.actor_id, cloned.actor_id);
    }

    /// Test proof with different verification levels
    #[test]
    fn test_verification_levels() {
        let levels = vec!["none", "basic", "strict"];

        for level in levels {
            let policy = AuditPolicy {
                policy_id: format!("policy-{}", level),
                require_proof: level != "none",
                verification_level: level.to_string(),
                retention_days: 90,
            };

            assert_eq!(policy.verification_level, level);
        }
    }

    /// Test different retention periods
    #[test]
    fn test_retention_periods() {
        let periods = vec![7, 30, 90, 365];

        for days in periods {
            let policy = AuditPolicy {
                policy_id: "policy-1".to_string(),
                require_proof: false,
                verification_level: "none".to_string(),
                retention_days: days,
            };

            assert_eq!(policy.retention_days, days);
        }
    }
}
