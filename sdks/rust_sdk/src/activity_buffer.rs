use crate::constants::*;
use crate::persistence::{PersistenceBackend, JsonFilePersistence, PersistentActivityRecord};
use crate::{Error, Result};
use std::collections::HashMap;
use std::sync::{Arc, RwLock};
use chrono::Utc;

/// Activity record for tracking message flow
#[derive(Debug, Clone)]
pub struct ActivityRecord {
    pub message_id: String,
    pub direction: String, // "in" | "out"
    pub envelope: serde_json::Value,
    pub ts_ms: i64,
    pub ack_stage: i32,
    pub error_code: i32,
    pub ack_note: String,
}

impl ActivityRecord {
    pub fn new(message_id: String, direction: String, envelope: serde_json::Value) -> Self {
        Self {
            message_id,
            direction,
            envelope,
            ts_ms: Utc::now().timestamp_millis(),
            ack_stage: ack_stage::ACK_STAGE_UNSPECIFIED,
            error_code: error_code::ERROR_CODE_UNSPECIFIED,
            ack_note: String::new(),
        }
    }

    pub fn ack(&mut self, stage: i32, error_code: i32, note: String) {
        self.ack_stage = stage;
        self.error_code = error_code;
        self.ack_note = note;
    }
}

/// In-memory activity buffer with simple reconciliation
#[derive(Debug)]
pub struct ActivityBuffer {
    by_id: HashMap<String, ActivityRecord>,
    order: Vec<String>,
    max_items: usize,
}

impl ActivityBuffer {
    pub fn new(max_items: usize) -> Self {
        Self {
            by_id: HashMap::new(),
            order: Vec::new(),
            max_items,
        }
    }

    fn prune_if_needed(&mut self) {
        while self.order.len() > self.max_items {
            let oldest = self.order.remove(0);
            self.by_id.remove(&oldest);
        }
    }

    pub fn record_incoming(&mut self, envelope: serde_json::Value) -> Result<ActivityRecord> {
        let message_id = envelope
            .get("message_id")
            .and_then(|v| v.as_str())
            .ok_or_else(|| Error::InvalidEnvelope("Missing message_id".to_string()))?
            .to_string();

        let record = ActivityRecord::new(message_id.clone(), "in".to_string(), envelope);
        self.by_id.insert(message_id.clone(), record.clone());
        self.order.push(message_id);
        self.prune_if_needed();
        
        Ok(record)
    }

    pub fn record_outgoing(&mut self, envelope: serde_json::Value) -> Result<ActivityRecord> {
        let message_id = envelope
            .get("message_id")
            .and_then(|v| v.as_str())
            .ok_or_else(|| Error::InvalidEnvelope("Missing message_id".to_string()))?
            .to_string();

        let record = ActivityRecord::new(message_id.clone(), "out".to_string(), envelope);
        self.by_id.insert(message_id.clone(), record.clone());
        self.order.push(message_id);
        self.prune_if_needed();
        
        Ok(record)
    }

    pub fn ack(&mut self, ack: &serde_json::Value) -> Option<&mut ActivityRecord> {
        let target = ack
            .get("ack_for_message_id")
            .and_then(|v| v.as_str())?
            .to_string();

        let record = self.by_id.get_mut(&target)?;
        
        let stage = ack
            .get("ack_stage")
            .and_then(|v| v.as_i64())
            .unwrap_or(ack_stage::ACK_STAGE_UNSPECIFIED as i64) as i32;
        
        let error_code = ack
            .get("error_code")
            .and_then(|v| v.as_i64())
            .unwrap_or(error_code::ERROR_CODE_UNSPECIFIED as i64) as i32;
        
        let note = ack
            .get("note")
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .to_string();

        record.ack(stage, error_code, note);
        Some(record)
    }

    pub fn get(&self, message_id: &str) -> Option<&ActivityRecord> {
        self.by_id.get(message_id)
    }

    pub fn unacked(&self) -> Vec<&ActivityRecord> {
        self.by_id
            .values()
            .filter(|r| matches!(r.ack_stage, 
                ack_stage::ACK_STAGE_UNSPECIFIED | 
                ack_stage::RECEIVED | 
                ack_stage::READ
            ))
            .collect()
    }

    pub fn recent(&self, n: usize) -> Vec<&ActivityRecord> {
        let start = if self.order.len() > n { self.order.len() - n } else { 0 };
        
        self.order[start..]
            .iter()
            .filter_map(|id| self.by_id.get(id))
            .collect()
    }
}

/// Thread-safe persistent activity buffer
pub struct PersistentActivityBuffer {
    inner: Arc<RwLock<PersistentActivityBufferInner>>,
}

struct PersistentActivityBufferInner {
    by_id: HashMap<String, PersistentActivityRecord>,
    order: Vec<String>,
    max_items: usize,
    persistence: Box<dyn PersistenceBackend>,
    dirty: bool,
}

impl PersistentActivityBuffer {
    pub fn new(max_items: usize, persistence: Option<Box<dyn PersistenceBackend>>) -> Result<Self> {
        let persistence = persistence.unwrap_or_else(|| Box::new(JsonFilePersistence::default()));
        
        let mut inner = PersistentActivityBufferInner {
            by_id: HashMap::new(),
            order: Vec::new(),
            max_items,
            persistence,
            dirty: false,
        };

        // Load existing data
        inner.load_from_persistence()?;

        Ok(Self {
            inner: Arc::new(RwLock::new(inner)),
        })
    }

    pub fn record_incoming(&self, envelope: serde_json::Value) -> Result<PersistentActivityRecord> {
        let mut inner = self.inner.write().map_err(|_| Error::Internal("Lock poisoned".to_string()))?;
        
        let message_id = envelope
            .get("message_id")
            .and_then(|v| v.as_str())
            .ok_or_else(|| Error::InvalidEnvelope("Missing message_id".to_string()))?
            .to_string();

        let record = PersistentActivityRecord::new(message_id.clone(), "in".to_string(), envelope);
        inner.by_id.insert(message_id.clone(), record.clone());
        inner.order.push(message_id);
        inner.prune_if_needed();
        inner.dirty = true;
        
        Ok(record)
    }

    pub fn record_outgoing(&self, envelope: serde_json::Value) -> Result<PersistentActivityRecord> {
        let mut inner = self.inner.write().map_err(|_| Error::Internal("Lock poisoned".to_string()))?;
        
        let message_id = envelope
            .get("message_id")
            .and_then(|v| v.as_str())
            .ok_or_else(|| Error::InvalidEnvelope("Missing message_id".to_string()))?
            .to_string();

        let record = PersistentActivityRecord::new(message_id.clone(), "out".to_string(), envelope);
        inner.by_id.insert(message_id.clone(), record.clone());
        inner.order.push(message_id);
        inner.prune_if_needed();
        inner.dirty = true;
        
        Ok(record)
    }

    pub fn ack(&self, ack: &serde_json::Value) -> Result<Option<PersistentActivityRecord>> {
        let mut inner = self.inner.write().map_err(|_| Error::Internal("Lock poisoned".to_string()))?;
        
        let target = ack
            .get("ack_for_message_id")
            .and_then(|v| v.as_str())
            .ok_or_else(|| Error::InvalidEnvelope("Missing ack_for_message_id".to_string()))?
            .to_string();

        if let Some(record) = inner.by_id.get_mut(&target) {
            let stage = ack
                .get("ack_stage")
                .and_then(|v| v.as_i64())
                .unwrap_or(ack_stage::ACK_STAGE_UNSPECIFIED as i64) as i32;
            
            let error_code = ack
                .get("error_code")
                .and_then(|v| v.as_i64())
                .unwrap_or(error_code::ERROR_CODE_UNSPECIFIED as i64) as i32;
            
            let note = ack
                .get("note")
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .to_string();

            record.ack(stage, error_code, note);
            let result = record.clone();
            
            // Release the mutable borrow before accessing inner.dirty
            let _ = record;
            inner.dirty = true;
            
            Ok(Some(result))
        } else {
            Ok(None)
        }
    }

    pub fn get(&self, message_id: &str) -> Result<Option<PersistentActivityRecord>> {
        let inner = self.inner.read().map_err(|_| Error::Internal("Lock poisoned".to_string()))?;
        Ok(inner.by_id.get(message_id).cloned())
    }

    pub fn unacked(&self) -> Result<Vec<PersistentActivityRecord>> {
        let inner = self.inner.read().map_err(|_| Error::Internal("Lock poisoned".to_string()))?;
        let records = inner
            .by_id
            .values()
            .filter(|r| matches!(r.ack_stage, 
                ack_stage::ACK_STAGE_UNSPECIFIED | 
                ack_stage::RECEIVED | 
                ack_stage::READ
            ))
            .cloned()
            .collect();
        Ok(records)
    }

    pub fn recent(&self, n: usize) -> Result<Vec<PersistentActivityRecord>> {
        let inner = self.inner.read().map_err(|_| Error::Internal("Lock poisoned".to_string()))?;
        let start = if inner.order.len() > n { inner.order.len() - n } else { 0 };
        
        let records = inner.order[start..]
            .iter()
            .filter_map(|id| inner.by_id.get(id))
            .cloned()
            .collect();
        
        Ok(records)
    }

    pub fn flush(&self) -> Result<()> {
        let mut inner = self.inner.write().map_err(|_| Error::Internal("Lock poisoned".to_string()))?;
        inner.save_to_persistence()
    }

    pub fn reconcile(&self) -> Result<Vec<PersistentActivityRecord>> {
        let unacked = self.unacked()?;
        let outgoing_unacked = unacked
            .into_iter()
            .filter(|r| r.direction == "out")
            .collect();
        
        Ok(outgoing_unacked)
    }

    pub fn clear(&self) -> Result<()> {
        let mut inner = self.inner.write().map_err(|_| Error::Internal("Lock poisoned".to_string()))?;
        inner.by_id.clear();
        inner.order.clear();
        inner.persistence.clear()?;
        inner.dirty = false;
        Ok(())
    }
}

impl PersistentActivityBufferInner {
    fn load_from_persistence(&mut self) -> Result<()> {
        match self.persistence.load_records() {
            Ok((records_data, order)) => {
                self.by_id = records_data;
                self.order = order;
                self.prune_if_needed();
                tracing::info!("Loaded {} records from persistence", self.by_id.len());
                Ok(())
            }
            Err(e) => {
                tracing::warn!("Failed to load from persistence: {}", e);
                self.by_id.clear();
                self.order.clear();
                Ok(())
            }
        }
    }

    fn save_to_persistence(&mut self) -> Result<()> {
        if !self.dirty {
            return Ok(());
        }

        self.persistence.save_records(self.by_id.clone(), self.order.clone())?;
        self.dirty = false;
        Ok(())
    }

    fn prune_if_needed(&mut self) {
        while self.order.len() > self.max_items {
            let oldest = self.order.remove(0);
            self.by_id.remove(&oldest);
            self.dirty = true;
        }
    }
}

impl Drop for PersistentActivityBuffer {
    fn drop(&mut self) {
        // Best effort save on drop
        if let Ok(mut inner) = self.inner.write() {
            let _ = inner.save_to_persistence();
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::persistence::JsonFilePersistence;
    use serde_json::json;
    use tempfile::NamedTempFile;
    use crate::constants;

    #[test]
    fn test_activity_buffer_creation() {
        let buffer = ActivityBuffer::new(100);
        assert_eq!(buffer.capacity(), 100);
        assert_eq!(buffer.len(), 0);
        assert!(buffer.is_empty());
        assert!(buffer.unacked().unwrap().is_empty());
    }

    #[test]
    fn test_activity_buffer_record_incoming() {
        let mut buffer = ActivityBuffer::new(10);
        
        let message = json!({
            "message_id": "msg-1",
            "producer_id": "test-agent",
            "message_type": constants::message_type::DATA,
            "payload": "test data"
        });

        let record = buffer.record_incoming(message.clone()).unwrap();
        
        assert_eq!(record.message_id, "msg-1");
        assert_eq!(record.producer_id, "test-agent");
        assert_eq!(record.direction, "in");
        assert_eq!(record.ack_stage, constants::ack_stage::ACK_STAGE_UNSPECIFIED);
        assert_eq!(buffer.len(), 1);
        assert!(!buffer.is_empty());
    }

    #[test]
    fn test_activity_buffer_ack_processing() {
        let mut buffer = ActivityBuffer::new(10);
        
        // Record incoming message
        let message = json!({
            "message_id": "msg-ack-test",
            "producer_id": "test-agent",
            "message_type": constants::message_type::DATA,
            "payload": "ack test data"
        });

        buffer.record_incoming(message).unwrap();
        
        // Send ACK
        let ack = json!({
            "ack_for_message_id": "msg-ack-test",
            "ack_stage": constants::ack_stage::RECEIVED,
            "error_code": constants::error_code::ERROR_CODE_UNSPECIFIED,
            "note": "Message received successfully"
        });

        let ack_result = buffer.ack(&ack).unwrap();
        assert!(ack_result.is_some());
        
        let updated_record = ack_result.unwrap();
        assert_eq!(updated_record.ack_stage, constants::ack_stage::RECEIVED);
        assert_eq!(updated_record.ack_note, "Message received successfully");
    }

    #[test]
    fn test_persistent_activity_buffer_creation() {
        let temp_file = NamedTempFile::new().unwrap();
        let persistence = Box::new(JsonFilePersistence::new(temp_file.path()));
        
        let buffer = PersistentActivityBuffer::new(50, Some(persistence));
        assert!(buffer.is_ok());
        
        let buffer = buffer.unwrap();
        assert_eq!(buffer.capacity(), 50);
        assert!(buffer.is_empty());
    }

    #[test]
    fn test_activity_buffer_capacity_management() {
        let mut buffer = ActivityBuffer::new(3);
        
        // Add more messages than capacity
        for i in 1..=5 {
            let message = json!({
                "message_id": format!("capacity-{}", i),
                "producer_id": "test-agent",
                "message_type": constants::message_type::DATA,
                "payload": format!("data-{}", i)
            });
            buffer.record_incoming(message).unwrap();
        }

        // Should only keep the most recent 3 messages
        assert_eq!(buffer.len(), 3);
        
        let all_records = buffer.recent(10).unwrap();
        assert_eq!(all_records.len(), 3);
        assert_eq!(all_records[0].message_id, "capacity-5");
        assert_eq!(all_records[2].message_id, "capacity-3");
    }

    #[test]
    fn test_activity_buffer_error_handling() {
        let mut buffer = ActivityBuffer::new(10);
        
        // Test with invalid message (missing required fields)
        let invalid_message = json!({"incomplete": "message"});
        let result = buffer.record_incoming(invalid_message);
        assert!(result.is_err());

        // Test ACK for non-existent message
        let ack_for_missing = json!({
            "ack_for_message_id": "does-not-exist",
            "ack_stage": constants::ack_stage::RECEIVED,
            "error_code": constants::error_code::ERROR_CODE_UNSPECIFIED,
            "note": "test"
        });
        
        let ack_result = buffer.ack(&ack_for_missing);
        assert!(ack_result.is_none());
    }
}