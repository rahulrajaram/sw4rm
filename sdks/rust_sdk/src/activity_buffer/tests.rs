//! Comprehensive unit tests for activity buffer operations

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
    fn test_activity_buffer_record_outgoing() {
        let mut buffer = ActivityBuffer::new(10);
        
        let message = json!({
            "message_id": "msg-out-1",
            "producer_id": "test-agent",
            "message_type": constants::message_type::DATA,
            "payload": "outgoing data"
        });

        let record = buffer.record_outgoing(message.clone()).unwrap();
        
        assert_eq!(record.message_id, "msg-out-1");
        assert_eq!(record.direction, "out");
        assert_eq!(record.ack_stage, constants::ack_stage::ACK_STAGE_UNSPECIFIED);
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
    fn test_activity_buffer_ack_lifecycle() {
        let mut buffer = ActivityBuffer::new(10);
        
        // Record message
        let message = json!({
            "message_id": "lifecycle-test",
            "producer_id": "test-agent",
            "message_type": constants::message_type::DATA,
            "payload": "lifecycle test"
        });

        buffer.record_incoming(message).unwrap();
        
        // Test full ACK lifecycle: RECEIVED -> READ -> FULFILLED
        let stages = [
            (constants::ack_stage::RECEIVED, "Received"),
            (constants::ack_stage::READ, "Read and processing"),
            (constants::ack_stage::FULFILLED, "Completed successfully")
        ];

        for (stage, note) in stages {
            let ack = json!({
                "ack_for_message_id": "lifecycle-test",
                "ack_stage": stage,
                "error_code": constants::error_code::ERROR_CODE_UNSPECIFIED,
                "note": note
            });

            let result = buffer.ack(&ack).unwrap().unwrap();
            assert_eq!(result.ack_stage, stage);
            assert_eq!(result.ack_note, note);
        }

        // Check that message is no longer unacked
        let unacked = buffer.unacked().unwrap();
        assert!(unacked.is_empty());
    }

    #[test]
    fn test_activity_buffer_unacked_messages() {
        let mut buffer = ActivityBuffer::new(10);
        
        // Add several messages
        for i in 1..=5 {
            let message = json!({
                "message_id": format!("msg-{}", i),
                "producer_id": "test-agent",
                "message_type": constants::message_type::DATA,
                "payload": format!("data-{}", i)
            });
            buffer.record_incoming(message).unwrap();
        }

        let unacked = buffer.unacked().unwrap();
        assert_eq!(unacked.len(), 5);

        // ACK a couple messages
        for i in 1..=2 {
            let ack = json!({
                "ack_for_message_id": format!("msg-{}", i),
                "ack_stage": constants::ack_stage::FULFILLED,
                "error_code": constants::error_code::ERROR_CODE_UNSPECIFIED,
                "note": "Fulfilled"
            });
            buffer.ack(&ack).unwrap();
        }

        let remaining_unacked = buffer.unacked().unwrap();
        assert_eq!(remaining_unacked.len(), 3);
    }

    #[test]
    fn test_activity_buffer_recent_messages() {
        let mut buffer = ActivityBuffer::new(100);
        
        // Add messages with different timestamps
        for i in 1..=10 {
            let message = json!({
                "message_id": format!("recent-{}", i),
                "producer_id": "test-agent",
                "message_type": constants::message_type::DATA,
                "payload": format!("recent-data-{}", i)
            });
            buffer.record_incoming(message).unwrap();
            
            // Small delay to ensure different timestamps
            std::thread::sleep(std::time::Duration::from_millis(1));
        }

        let recent = buffer.recent(5).unwrap();
        assert_eq!(recent.len(), 5);
        
        // Should be in reverse chronological order (newest first)
        assert_eq!(recent[0].message_id, "recent-10");
        assert_eq!(recent[4].message_id, "recent-6");
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
    fn test_activity_buffer_get_by_id() {
        let mut buffer = ActivityBuffer::new(10);
        
        let message = json!({
            "message_id": "findable-msg",
            "producer_id": "test-agent",
            "message_type": constants::message_type::DATA,
            "payload": "findable data"
        });

        buffer.record_incoming(message).unwrap();
        
        let found = buffer.get_by_id("findable-msg").unwrap();
        assert!(found.is_some());
        assert_eq!(found.unwrap().message_id, "findable-msg");
        
        let not_found = buffer.get_by_id("non-existent");
        assert!(not_found.is_none());
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
    fn test_persistent_activity_buffer_persistence() {
        let temp_file = NamedTempFile::new().unwrap();
        let file_path = temp_file.path().to_path_buf();
        
        // Create buffer and add data
        {
            let persistence = Box::new(JsonFilePersistence::new(&file_path));
            let buffer = PersistentActivityBuffer::new(10, Some(persistence)).unwrap();
            
            let message = json!({
                "message_id": "persistent-test",
                "producer_id": "test-agent",
                "message_type": constants::message_type::DATA,
                "payload": "persistent data"
            });
            
            buffer.record_incoming(message).unwrap();
            buffer.flush().unwrap();
        }
        
        // Recreate buffer and verify data persisted
        {
            let new_persistence = Box::new(JsonFilePersistence::new(&file_path));
            let new_buffer = PersistentActivityBuffer::new(10, Some(new_persistence)).unwrap();
            
            let records = new_buffer.recent(10).unwrap();
            assert_eq!(records.len(), 1);
            assert_eq!(records[0].message_id, "persistent-test");
        }
    }

    #[test]
    fn test_persistent_buffer_flush_and_reload() {
        let temp_file = NamedTempFile::new().unwrap();
        let persistence = Box::new(JsonFilePersistence::new(temp_file.path()));
        let buffer = PersistentActivityBuffer::new(10, Some(persistence)).unwrap();
        
        // Add multiple messages
        for i in 1..=3 {
            let message = json!({
                "message_id": format!("flush-test-{}", i),
                "producer_id": "test-agent",
                "message_type": constants::message_type::DATA,
                "payload": format!("flush-data-{}", i)
            });
            buffer.record_incoming(message).unwrap();
        }

        // Manually flush
        buffer.flush().unwrap();
        
        // Add one more message and ACK one
        let message = json!({
            "message_id": "flush-test-4",
            "producer_id": "test-agent",
            "message_type": constants::message_type::DATA,
            "payload": "flush-data-4"
        });
        buffer.record_incoming(message).unwrap();
        
        let ack = json!({
            "ack_for_message_id": "flush-test-1",
            "ack_stage": constants::ack_stage::FULFILLED,
            "error_code": constants::error_code::ERROR_CODE_UNSPECIFIED,
            "note": "Test complete"
        });
        buffer.ack(&ack).unwrap();
        
        // Final flush and verify state
        buffer.flush().unwrap();
        
        let final_records = buffer.recent(10).unwrap();
        assert_eq!(final_records.len(), 4);
        
        let unacked = buffer.unacked().unwrap();
        assert_eq!(unacked.len(), 3); // 4 total - 1 acked
    }

    #[test]
    fn test_activity_buffer_concurrent_access() {
        use std::sync::Arc;
        use std::sync::Mutex;
        use std::thread;

        let buffer = Arc::new(Mutex::new(ActivityBuffer::new(100)));
        let mut handles = Vec::new();

        // Spawn multiple threads to add messages concurrently
        for i in 0..10 {
            let buffer_clone = Arc::clone(&buffer);
            let handle = thread::spawn(move || {
                for j in 0..5 {
                    let message = json!({
                        "message_id": format!("concurrent-{}-{}", i, j),
                        "producer_id": format!("agent-{}", i),
                        "message_type": constants::message_type::DATA,
                        "payload": format!("concurrent-data-{}-{}", i, j)
                    });
                    
                    let mut buf = buffer_clone.lock().unwrap();
                    buf.record_incoming(message).unwrap();
                }
            });
            handles.push(handle);
        }

        // Wait for all threads to complete
        for handle in handles {
            handle.join().unwrap();
        }

        let buffer = buffer.lock().unwrap();
        assert_eq!(buffer.len(), 50); // 10 threads * 5 messages each
    }

    #[test]
    fn test_activity_buffer_performance_characteristics() {
        let mut buffer = ActivityBuffer::new(1000);
        
        let start = std::time::Instant::now();
        
        // Add many messages
        for i in 0..1000 {
            let message = json!({
                "message_id": format!("perf-{:04}", i),
                "producer_id": "perf-agent",
                "message_type": constants::message_type::DATA,
                "payload": format!("performance test data {}", i)
            });
            buffer.record_incoming(message).unwrap();
        }
        
        let insert_time = start.elapsed();
        
        let start = std::time::Instant::now();
        
        // Process ACKs for half the messages
        for i in 0..500 {
            let ack = json!({
                "ack_for_message_id": format!("perf-{:04}", i),
                "ack_stage": constants::ack_stage::FULFILLED,
                "error_code": constants::error_code::ERROR_CODE_UNSPECIFIED,
                "note": "Performance test ACK"
            });
            buffer.ack(&ack).unwrap();
        }
        
        let ack_time = start.elapsed();
        
        // Verify final state
        assert_eq!(buffer.len(), 1000);
        let unacked = buffer.unacked().unwrap();
        assert_eq!(unacked.len(), 500);
        
        // Basic performance assertions (adjust thresholds based on requirements)
        assert!(insert_time.as_millis() < 1000, "Insert time too slow: {:?}", insert_time);
        assert!(ack_time.as_millis() < 500, "ACK processing too slow: {:?}", ack_time);
    }

    #[test]
    fn test_activity_buffer_edge_cases() {
        let mut buffer = ActivityBuffer::new(1);
        
        // Test with zero capacity buffer (edge case)
        let zero_buffer = ActivityBuffer::new(0);
        assert_eq!(zero_buffer.capacity(), 0);
        assert!(zero_buffer.is_empty());

        // Test with single capacity
        let message1 = json!({
            "message_id": "edge-1",
            "producer_id": "test",
            "message_type": constants::message_type::DATA,
            "payload": "first"
        });
        
        let message2 = json!({
            "message_id": "edge-2", 
            "producer_id": "test",
            "message_type": constants::message_type::DATA,
            "payload": "second"
        });

        buffer.record_incoming(message1).unwrap();
        assert_eq!(buffer.len(), 1);
        
        // Adding second message should evict the first
        buffer.record_incoming(message2).unwrap();
        assert_eq!(buffer.len(), 1);
        
        let recent = buffer.recent(10).unwrap();
        assert_eq!(recent.len(), 1);
        assert_eq!(recent[0].message_id, "edge-2");
    }
}