use crate::{Error, Result};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::fs;
use std::path::Path;
use chrono::Utc;

/// Trait for persistence backends
pub trait PersistenceBackend: Send + Sync {
    fn save_records(&mut self, records: HashMap<String, PersistentActivityRecord>, order: Vec<String>) -> Result<()>;
    fn load_records(&mut self) -> Result<(HashMap<String, PersistentActivityRecord>, Vec<String>)>;
    fn clear(&mut self) -> Result<()>;
}

/// JSON file-based persistence backend
#[derive(Debug)]
pub struct JsonFilePersistence {
    file_path: std::path::PathBuf,
}

impl JsonFilePersistence {
    pub fn new(file_path: impl AsRef<Path>) -> Self {
        Self {
            file_path: file_path.as_ref().to_path_buf(),
        }
    }
}

impl Default for JsonFilePersistence {
    fn default() -> Self {
        Self::new("sw4rm_activity.json")
    }
}

#[derive(Debug, Serialize, Deserialize)]
struct PersistedData {
    records: HashMap<String, PersistentActivityRecord>,
    order: Vec<String>,
    version: String,
}

impl PersistenceBackend for JsonFilePersistence {
    fn save_records(&mut self, records: HashMap<String, PersistentActivityRecord>, order: Vec<String>) -> Result<()> {
        let data = PersistedData {
            records,
            order,
            version: "1.0".to_string(),
        };

        // Atomic write: write to temp file, then rename
        let temp_path = self.file_path.with_extension("tmp");
        let json_data = serde_json::to_string_pretty(&data)
            .map_err(|e| Error::Serialization(e))?;
        
        fs::write(&temp_path, json_data)
            .map_err(|e| Error::Io(e))?;
        
        fs::rename(temp_path, &self.file_path)
            .map_err(|e| Error::Io(e))?;

        Ok(())
    }

    fn load_records(&mut self) -> Result<(HashMap<String, PersistentActivityRecord>, Vec<String>)> {
        if !self.file_path.exists() {
            return Ok((HashMap::new(), Vec::new()));
        }

        let content = fs::read_to_string(&self.file_path)
            .map_err(|e| Error::Io(e))?;
        
        let data: PersistedData = serde_json::from_str(&content)
            .map_err(|e| Error::Serialization(e))?;
        
        // Validate data consistency
        let valid_order: Vec<String> = data.order
            .into_iter()
            .filter(|id| data.records.contains_key(id))
            .collect();

        Ok((data.records, valid_order))
    }

    fn clear(&mut self) -> Result<()> {
        if self.file_path.exists() {
            fs::remove_file(&self.file_path)
                .map_err(|e| Error::Io(e))?;
        }
        Ok(())
    }
}

/// Serializable activity record for persistence
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PersistentActivityRecord {
    pub message_id: String,
    pub direction: String,
    pub envelope: serde_json::Value,
    pub ts_ms: i64,
    pub ack_stage: i32,
    pub error_code: i32,
    pub ack_note: String,
}

impl PersistentActivityRecord {
    pub fn new(message_id: String, direction: String, envelope: serde_json::Value) -> Self {
        Self {
            message_id,
            direction,
            envelope,
            ts_ms: Utc::now().timestamp_millis(),
            ack_stage: crate::constants::ack_stage::ACK_STAGE_UNSPECIFIED,
            error_code: crate::constants::error_code::ERROR_CODE_UNSPECIFIED,
            ack_note: String::new(),
        }
    }

    pub fn ack(&mut self, stage: i32, error_code: i32, note: String) {
        self.ack_stage = stage;
        self.error_code = error_code;
        self.ack_note = note;
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::NamedTempFile;

    #[test]
    fn test_json_persistence_round_trip() {
        let temp_file = NamedTempFile::new().unwrap();
        let mut persistence = JsonFilePersistence::new(temp_file.path());

        let mut records = HashMap::new();
        let record = PersistentActivityRecord::new(
            "test-id".to_string(),
            "in".to_string(),
            serde_json::json!({"test": "data"}),
        );
        records.insert("test-id".to_string(), record);
        let order = vec!["test-id".to_string()];

        // Save
        persistence.save_records(records.clone(), order.clone()).unwrap();

        // Load
        let (loaded_records, loaded_order) = persistence.load_records().unwrap();

        assert_eq!(loaded_records.len(), 1);
        assert_eq!(loaded_order, order);
        assert!(loaded_records.contains_key("test-id"));
    }

    #[test]
    fn test_json_persistence_empty_file() {
        let temp_file = NamedTempFile::new().unwrap();
        temp_file.as_file().set_len(0).unwrap(); // Empty file
        
        let mut persistence = JsonFilePersistence::new(temp_file.path());
        let (records, order) = persistence.load_records().unwrap();

        assert!(records.is_empty());
        assert!(order.is_empty());
    }

    #[test] 
    fn test_json_persistence_nonexistent_file() {
        let mut persistence = JsonFilePersistence::new("/nonexistent/path/file.json");
        let (records, order) = persistence.load_records().unwrap();

        assert!(records.is_empty());
        assert!(order.is_empty());
    }

    #[test]
    fn test_json_persistence_error_handling() {
        // Test with invalid file path
        let invalid_path = Path::new("/invalid/path/that/does/not/exist");
        let mut persistence = JsonFilePersistence::new(invalid_path);
        
        // Should create empty records when file doesn't exist but path is valid
        let (records, order) = persistence.load_records().unwrap();
        assert!(records.is_empty());
        assert!(order.is_empty());
        
        // Try to save to invalid path (should fail)
        let mut test_records = HashMap::new();
        test_records.insert("test".to_string(), PersistentActivityRecord {
            message_id: "test".to_string(),
            direction: "in".to_string(),
            envelope: serde_json::json!({"producer_id": "test"}),
            ts_ms: Utc::now().timestamp_millis(),
            ack_stage: 1,
            error_code: 0,
            ack_note: "".to_string(),
        });
        
        let result = persistence.save_records(test_records, vec!["test".to_string()]);
        assert!(result.is_err());
    }

    #[test]
    fn test_json_persistence_concurrent_access() {
        use std::sync::Arc;
        use std::sync::Mutex;
        use std::thread;
        
        let temp_file = tempfile::NamedTempFile::new().unwrap();
        let file_path = temp_file.path().to_path_buf();
        
        let persistence = Arc::new(Mutex::new(JsonFilePersistence::new(&file_path)));
        let mut handles = Vec::new();
        
        // Spawn multiple threads to write different records
        for i in 0..5 {
            let persistence_clone = Arc::clone(&persistence);
            let handle = thread::spawn(move || {
                let mut records = HashMap::new();
                records.insert(format!("msg-{}", i), PersistentActivityRecord {
                    message_id: format!("msg-{}", i),
                    producer_id: format!("agent-{}", i),
                    direction: "in".to_string(),
                    ack_stage: 1,
                    error_code: 0,
                    ack_note: "concurrent test".to_string(),
                    message_data: serde_json::json!({"thread": i}),
                    timestamp: Utc::now(),
                });
                
                let mut p = persistence_clone.lock().unwrap();
                p.save_records(records, vec![format!("msg-{}", i)]).unwrap();
            });
            handles.push(handle);
        }
        
        // Wait for all threads
        for handle in handles {
            handle.join().unwrap();
        }
        
        // The last write wins, so we should have one record
        let mut p = persistence.lock().unwrap();
        let (records, order) = p.load_records().unwrap();
        assert_eq!(records.len(), 1);
        assert_eq!(order.len(), 1);
    }

    #[test]
    fn test_persistent_activity_record_serialization() {
        let record = PersistentActivityRecord {
            message_id: "serialize-test".to_string(),
            producer_id: "test-agent".to_string(),
            direction: "in".to_string(),
            ack_stage: 2,
            error_code: 0,
            ack_note: "serialization test".to_string(),
            message_data: serde_json::json!({
                "test": "data",
                "number": 42,
                "array": [1, 2, 3]
            }),
            timestamp: Utc::now(),
        };
        
        // Test JSON serialization
        let json_str = serde_json::to_string(&record).unwrap();
        assert!(json_str.contains("serialize-test"));
        assert!(json_str.contains("test-agent"));
        assert!(json_str.contains("serialization test"));
        
        // Test JSON deserialization
        let deserialized: PersistentActivityRecord = serde_json::from_str(&json_str).unwrap();
        assert_eq!(deserialized.message_id, record.message_id);
        assert_eq!(deserialized.producer_id, record.producer_id);
        assert_eq!(deserialized.direction, record.direction);
        assert_eq!(deserialized.ack_stage, record.ack_stage);
        assert_eq!(deserialized.error_code, record.error_code);
        assert_eq!(deserialized.ack_note, record.ack_note);
        assert_eq!(deserialized.message_data, record.message_data);
    }

    #[test]
    fn test_json_persistence_large_data() {
        let temp_file = tempfile::NamedTempFile::new().unwrap();
        let mut persistence = JsonFilePersistence::new(temp_file.path());
        
        // Create a large dataset
        let mut records = HashMap::new();
        let mut order = Vec::new();
        
        for i in 0..100 {
            let record = PersistentActivityRecord {
                message_id: format!("large-msg-{:03}", i),
                producer_id: "large-data-agent".to_string(),
                direction: if i % 2 == 0 { "in" } else { "out" }.to_string(),
                ack_stage: (i % 5) as i32,
                error_code: 0,
                ack_note: format!("Large data test message {}", i),
                message_data: serde_json::json!({
                    "index": i,
                    "data": "x".repeat(100), // 100 character string
                    "metadata": {
                        "created": format!("2024-01-{:02}T00:00:00Z", (i % 28) + 1),
                        "tags": vec![format!("tag-{}", i % 10), "large-test"]
                    }
                }),
                timestamp: Utc::now(),
            };
            
            let msg_id = record.message_id.clone();
            records.insert(msg_id.clone(), record);
            order.push(msg_id);
        }
        
        // Save large dataset
        persistence.save_records(records.clone(), order.clone()).unwrap();
        
        // Load and verify
        let (loaded_records, loaded_order) = persistence.load_records().unwrap();
        
        assert_eq!(loaded_records.len(), 100);
        assert_eq!(loaded_order.len(), 100);
        
        // Verify some specific records
        assert!(loaded_records.contains_key("large-msg-000"));
        assert!(loaded_records.contains_key("large-msg-050"));
        assert!(loaded_records.contains_key("large-msg-099"));
        
        let first_record = &loaded_records["large-msg-000"];
        assert_eq!(first_record.producer_id, "large-data-agent");
        assert_eq!(first_record.direction, "in");
        assert_eq!(first_record.message_data["index"], 0);
    }

    #[test]
    fn test_json_persistence_special_characters() {
        let temp_file = tempfile::NamedTempFile::new().unwrap();
        let mut persistence = JsonFilePersistence::new(temp_file.path());
        
        let mut records = HashMap::new();
        
        // Test record with special characters
        let record = PersistentActivityRecord {
            message_id: "special-chars-test".to_string(),
            direction: "in".to_string(),
            envelope: serde_json::json!({
                "message_id": "special-chars-test",
                "producer_id": "special-agent",
                "unicode": "Hello 世界 🌍",
                "quotes": "He said \"hello\" to me",
                "backslashes": "C:\\Windows\\System32",
                "newlines": "Line 1\nLine 2\rLine 3",
                "emoji": "🎉🎊🚀💖"
            }),
            ts_ms: Utc::now().timestamp_millis(),
            ack_stage: 1,
            error_code: 0,
            ack_note: "Special chars: åäöüñ 中文 🚀 \"quotes\" 'single' \\backslash".to_string(),
        };
        
        records.insert("special-chars-test".to_string(), record);
        
        // Save and load
        persistence.save_records(records, vec!["special-chars-test".to_string()]).unwrap();
        let (loaded_records, _) = persistence.load_records().unwrap();
        
        let loaded_record = &loaded_records["special-chars-test"];
        assert!(loaded_record.ack_note.contains("åäöüñ"));
        assert!(loaded_record.ack_note.contains("中文"));
        assert!(loaded_record.ack_note.contains("🚀"));
        assert_eq!(loaded_record.envelope["unicode"], "Hello 世界 🌍");
        assert_eq!(loaded_record.envelope["emoji"], "🎉🎊🚀💖");
    }

    #[test]
    fn test_json_persistence_file_corruption_recovery() {
        let temp_file = tempfile::NamedTempFile::new().unwrap();
        let file_path = temp_file.path().to_path_buf();
        
        // Write invalid JSON to file
        std::fs::write(&file_path, "invalid json content {").unwrap();
        
        let mut persistence = JsonFilePersistence::new(&file_path);
        
        // Loading corrupted file should return empty data (graceful degradation)
        let (records, order) = persistence.load_records().unwrap();
        assert!(records.is_empty());
        assert!(order.is_empty());
        
        // Should be able to write new data after corruption
        let mut new_records = HashMap::new();
        new_records.insert("recovery-test".to_string(), PersistentActivityRecord {
            message_id: "recovery-test".to_string(),
            producer_id: "recovery-agent".to_string(),
            direction: "in".to_string(),
            ack_stage: 1,
            error_code: 0,
            ack_note: "recovery test".to_string(),
            message_data: serde_json::json!({"recovered": true}),
            timestamp: Utc::now(),
        });
        
        persistence.save_records(new_records, vec!["recovery-test".to_string()]).unwrap();
        
        // Verify recovery worked
        let (recovered_records, _) = persistence.load_records().unwrap();
        assert_eq!(recovered_records.len(), 1);
        assert!(recovered_records.contains_key("recovery-test"));
    }

    #[test]
    fn test_persistence_backend_trait() {
        let temp_file = tempfile::NamedTempFile::new().unwrap();
        let mut persistence: Box<dyn PersistenceBackend> = Box::new(JsonFilePersistence::new(temp_file.path()));
        
        let mut records = HashMap::new();
        records.insert("trait-test".to_string(), PersistentActivityRecord {
            message_id: "trait-test".to_string(),
            producer_id: "trait-agent".to_string(),
            direction: "in".to_string(),
            ack_stage: 1,
            error_code: 0,
            ack_note: "testing trait".to_string(),
            message_data: serde_json::json!({"trait": "test"}),
            timestamp: Utc::now(),
        });
        
        // Test through trait interface
        persistence.save_records(records, vec!["trait-test".to_string()]).unwrap();
        let (loaded_records, loaded_order) = persistence.load_records().unwrap();
        
        assert_eq!(loaded_records.len(), 1);
        assert_eq!(loaded_order.len(), 1);
        assert!(loaded_records.contains_key("trait-test"));
        
        // Test clear
        persistence.clear().unwrap();
        let (empty_records, empty_order) = persistence.load_records().unwrap();
        assert!(empty_records.is_empty());
        assert!(empty_order.is_empty());
    }
}