use crate::{Error, Result};
use chrono::Utc;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::fs;
use std::path::Path;

/// Trait for persistence backends
pub trait PersistenceBackend: Send + Sync {
    fn save_records(
        &mut self,
        records: HashMap<String, PersistentActivityRecord>,
        order: Vec<String>,
    ) -> Result<()>;
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
    fn save_records(
        &mut self,
        records: HashMap<String, PersistentActivityRecord>,
        order: Vec<String>,
    ) -> Result<()> {
        let data = PersistedData {
            records,
            order,
            version: "1.0".to_string(),
        };

        // Atomic write: write to temp file, then rename
        let temp_path = self.file_path.with_extension("tmp");
        let json_data = serde_json::to_string_pretty(&data).map_err(Error::Serialization)?;

        fs::write(&temp_path, json_data).map_err(Error::Io)?;

        fs::rename(temp_path, &self.file_path).map_err(Error::Io)?;

        Ok(())
    }

    fn load_records(&mut self) -> Result<(HashMap<String, PersistentActivityRecord>, Vec<String>)> {
        if !self.file_path.exists() {
            return Ok((HashMap::new(), Vec::new()));
        }

        let content = fs::read_to_string(&self.file_path).map_err(Error::Io)?;

        if content.trim().is_empty() {
            return Ok((HashMap::new(), Vec::new()));
        }

        let data: PersistedData = match serde_json::from_str(&content) {
            Ok(d) => d,
            Err(_) => {
                // Gracefully handle corrupted/empty content by returning empty
                return Ok((HashMap::new(), Vec::new()));
            }
        };

        // Validate data consistency
        let valid_order: Vec<String> = data
            .order
            .into_iter()
            .filter(|id| data.records.contains_key(id))
            .collect();

        Ok((data.records, valid_order))
    }

    fn clear(&mut self) -> Result<()> {
        if self.file_path.exists() {
            fs::remove_file(&self.file_path).map_err(Error::Io)?;
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
        persistence
            .save_records(records.clone(), order.clone())
            .unwrap();

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
        test_records.insert(
            "test".to_string(),
            PersistentActivityRecord {
                message_id: "test".to_string(),
                direction: "in".to_string(),
                envelope: serde_json::json!({"producer_id": "test"}),
                ts_ms: Utc::now().timestamp_millis(),
                ack_stage: 1,
                error_code: 0,
                ack_note: "".to_string(),
            },
        );

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
                let id = format!("msg-{}", i);
                let env = serde_json::json!({
                    "message_id": id,
                    "producer_id": format!("agent-{}", i),
                    "thread": i
                });
                let mut rec = PersistentActivityRecord::new(id.clone(), "in".to_string(), env);
                rec.ack(1, 0, "concurrent test".to_string());
                records.insert(id.clone(), rec);

                let mut p = persistence_clone.lock().unwrap();
                p.save_records(records, vec![id]).unwrap();
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
        let mut record = PersistentActivityRecord::new(
            "serialize-test".to_string(),
            "in".to_string(),
            serde_json::json!({
                "message_id": "serialize-test",
                "producer_id": "test-agent",
                "test": "data",
                "number": 42,
                "array": [1,2,3]
            }),
        );
        record.ack(2, 0, "serialization test".to_string());

        // Test JSON serialization
        let json_str = serde_json::to_string(&record).unwrap();
        assert!(json_str.contains("serialize-test"));
        assert!(json_str.contains("test-agent"));
        assert!(json_str.contains("serialization test"));

        // Test JSON deserialization
        let deserialized: PersistentActivityRecord = serde_json::from_str(&json_str).unwrap();
        assert_eq!(deserialized.message_id, record.message_id);
        assert_eq!(deserialized.envelope["producer_id"], "test-agent");
        assert_eq!(deserialized.direction, record.direction);
        assert_eq!(deserialized.ack_stage, record.ack_stage);
        assert_eq!(deserialized.error_code, record.error_code);
        assert_eq!(deserialized.ack_note, record.ack_note);
        assert_eq!(deserialized.envelope["number"], 42);
    }

    #[test]
    fn test_json_persistence_large_data() {
        let temp_file = tempfile::NamedTempFile::new().unwrap();
        let mut persistence = JsonFilePersistence::new(temp_file.path());

        // Create a large dataset
        let mut records = HashMap::new();
        let mut order = Vec::new();

        for i in 0..100 {
            let id = format!("large-msg-{:03}", i);
            let mut rec = PersistentActivityRecord::new(
                id.clone(),
                if i % 2 == 0 { "in" } else { "out" }.to_string(),
                serde_json::json!({
                    "message_id": id,
                    "producer_id": "large-data-agent",
                    "index": i,
                    "data": "x".repeat(100),
                    "metadata": {
                        "created": format!("2024-01-{:02}T00:00:00Z", (i % 28) + 1),
                        "tags": [format!("tag-{}", i % 10), "large-test"]
                    }
                }),
            );
            rec.ack(i % 5, 0, format!("Large data test message {}", i));
            records.insert(id.clone(), rec);
            order.push(id);
        }

        // Save large dataset
        persistence
            .save_records(records.clone(), order.clone())
            .unwrap();

        // Load and verify
        let (loaded_records, loaded_order) = persistence.load_records().unwrap();

        assert_eq!(loaded_records.len(), 100);
        assert_eq!(loaded_order.len(), 100);

        // Verify some specific records
        assert!(loaded_records.contains_key("large-msg-000"));
        assert!(loaded_records.contains_key("large-msg-050"));
        assert!(loaded_records.contains_key("large-msg-099"));

        let first_record = &loaded_records["large-msg-000"];
        assert_eq!(first_record.envelope["producer_id"], "large-data-agent");
        assert_eq!(first_record.direction, "in");
        assert_eq!(first_record.envelope["index"], 0);
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
        persistence
            .save_records(records, vec!["special-chars-test".to_string()])
            .unwrap();
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
        let mut rec = PersistentActivityRecord::new(
            "recovery-test".to_string(),
            "in".to_string(),
            serde_json::json!({"message_id": "recovery-test", "producer_id": "recovery-agent", "recovered": true}),
        );
        rec.ack(1, 0, "recovery test".to_string());
        new_records.insert("recovery-test".to_string(), rec);

        persistence
            .save_records(new_records, vec!["recovery-test".to_string()])
            .unwrap();

        // Verify recovery worked
        let (recovered_records, _) = persistence.load_records().unwrap();
        assert_eq!(recovered_records.len(), 1);
        assert!(recovered_records.contains_key("recovery-test"));
    }

    #[test]
    fn test_persistence_backend_trait() {
        let temp_file = tempfile::NamedTempFile::new().unwrap();
        let mut persistence: Box<dyn PersistenceBackend> =
            Box::new(JsonFilePersistence::new(temp_file.path()));

        let mut records = HashMap::new();
        let mut rec = PersistentActivityRecord::new(
            "trait-test".to_string(),
            "in".to_string(),
            serde_json::json!({"message_id": "trait-test", "producer_id": "trait-agent", "trait": "test"}),
        );
        rec.ack(1, 0, "testing trait".to_string());
        records.insert("trait-test".to_string(), rec);

        // Test through trait interface
        persistence
            .save_records(records, vec!["trait-test".to_string()])
            .unwrap();
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
