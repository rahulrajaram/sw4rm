use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use uuid::Uuid;

/// Sequence number tracker for message ordering
#[derive(Debug)]
pub struct SequenceTracker {
    current: std::sync::atomic::AtomicU64,
}

impl Clone for SequenceTracker {
    fn clone(&self) -> Self {
        Self {
            current: std::sync::atomic::AtomicU64::new(
                self.current.load(std::sync::atomic::Ordering::SeqCst)
            ),
        }
    }
}

impl SequenceTracker {
    pub fn new(start: u64) -> Self {
        Self {
            current: std::sync::atomic::AtomicU64::new(start.saturating_sub(1)),
        }
    }

    pub fn next(&self) -> u64 {
        self.current.fetch_add(1, std::sync::atomic::Ordering::SeqCst) + 1
    }
}

impl Default for SequenceTracker {
    fn default() -> Self {
        Self::new(1)
    }
}

/// Preemption state for cooperative agent shutdown
#[derive(Debug, Clone, Default)]
pub struct PreemptionState {
    pub requested: bool,
    pub reason: Option<String>,
}

/// Agent descriptor for registration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AgentDescriptor {
    pub agent_id: String,
    pub name: String,
    pub description: String,
    pub version: String,
    pub capabilities: Vec<String>,
    pub metadata: HashMap<String, String>,
}

impl AgentDescriptor {
    pub fn new(agent_id: String, name: String) -> Self {
        Self {
            agent_id,
            name,
            description: String::new(),
            version: "0.1.0".to_string(),
            capabilities: Vec::new(),
            metadata: HashMap::new(),
        }
    }
}

/// Utility functions for UUID and timestamp generation
pub fn new_uuid() -> String {
    Uuid::new_v4().to_string()
}

pub fn now_hlc_stub() -> String {
    // Placeholder for HLC; using unix timestamp in milliseconds
    chrono::Utc::now().timestamp_millis().to_string()
}

pub fn make_idempotency_token(producer_id: &str, operation_type: &str, deterministic_hash: &str) -> String {
    format!("{}:{}:{}", producer_id, operation_type, deterministic_hash)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_sequence_tracker_creation() {
        let tracker = SequenceTracker::new(100);
        assert_eq!(tracker.next(), 100);
        assert_eq!(tracker.next(), 101);
        assert_eq!(tracker.next(), 102);
    }

    #[test]
    fn test_sequence_tracker_default() {
        let tracker = SequenceTracker::default();
        assert_eq!(tracker.next(), 1);
        assert_eq!(tracker.next(), 2);
        assert_eq!(tracker.next(), 3);
    }

    #[test]
    fn test_sequence_tracker_concurrent_access() {
        use std::sync::Arc;
        use std::thread;

        let tracker = Arc::new(SequenceTracker::new(1));
        let mut handles = Vec::new();

        // Spawn multiple threads to get sequence numbers
        for _ in 0..10 {
            let tracker_clone = Arc::clone(&tracker);
            let handle = thread::spawn(move || {
                let mut numbers = Vec::new();
                for _ in 0..10 {
                    numbers.push(tracker_clone.next());
                }
                numbers
            });
            handles.push(handle);
        }

        // Collect all numbers from all threads
        let mut all_numbers = Vec::new();
        for handle in handles {
            all_numbers.extend(handle.join().unwrap());
        }

        // Verify all numbers are unique and in expected range
        all_numbers.sort();
        assert_eq!(all_numbers.len(), 100);
        assert_eq!(all_numbers[0], 1);
        assert_eq!(all_numbers[99], 100);
        
        // Check for uniqueness
        all_numbers.dedup();
        assert_eq!(all_numbers.len(), 100);
    }

    #[test]
    fn test_preemption_manager_creation() {
        let manager = PreemptionState::new();
        assert!(!manager.is_preemption_requested());
        assert!(manager.get_preemption_reason().is_none());
    }

    #[test]
    fn test_preemption_manager_request() {
        let mut manager = PreemptionState::new();
        
        manager.request_preemption(Some("Test shutdown".to_string()));
        assert!(manager.is_preemption_requested());
        assert_eq!(manager.get_preemption_reason(), Some("Test shutdown".to_string()));
    }

    #[test]
    fn test_preemption_manager_request_without_reason() {
        let mut manager = PreemptionState::new();
        
        manager.request_preemption(None);
        assert!(manager.is_preemption_requested());
        assert!(manager.get_preemption_reason().is_none());
    }

    #[test]
    fn test_preemption_manager_clear() {
        let mut manager = PreemptionState::new();
        
        manager.request_preemption(Some("Test".to_string()));
        assert!(manager.is_preemption_requested());
        
        manager.clear_preemption();
        assert!(!manager.is_preemption_requested());
        assert!(manager.get_preemption_reason().is_none());
    }

    #[test]
    fn test_agent_descriptor_creation() {
        let descriptor = AgentDescriptor::new(
            "test-agent".to_string(),
            "Test Agent".to_string()
        );
        
        assert_eq!(descriptor.agent_id, "test-agent");
        assert_eq!(descriptor.name, "Test Agent");
        assert!(descriptor.description.is_empty());
        assert!(descriptor.capabilities.is_empty());
    }

    #[test]
    fn test_agent_descriptor_with_capabilities() {
        let capabilities = vec![
            "file-operations".to_string(),
            "web-requests".to_string(),
            "data-processing".to_string()
        ];
        
        let descriptor = AgentDescriptor::new(
            "capable-agent".to_string(),
            "Capable Agent".to_string()
        ).with_capabilities(capabilities.clone());
        
        assert_eq!(descriptor.capabilities, capabilities);
    }

    #[test]
    fn test_agent_descriptor_with_description() {
        let description = "An agent that performs various tasks for testing purposes";
        
        let descriptor = AgentDescriptor::new(
            "described-agent".to_string(),
            "Described Agent".to_string()
        ).with_description(description.to_string());
        
        assert_eq!(descriptor.description, description);
    }

    #[test]
    fn test_agent_descriptor_builder_pattern() {
        let descriptor = AgentDescriptor::new(
            "builder-agent".to_string(),
            "Builder Pattern Agent".to_string()
        )
        .with_description("Testing builder pattern".to_string())
        .with_capabilities(vec!["build".to_string(), "test".to_string()]);
        
        assert_eq!(descriptor.agent_id, "builder-agent");
        assert_eq!(descriptor.name, "Builder Pattern Agent");
        assert_eq!(descriptor.description, "Testing builder pattern");
        assert_eq!(descriptor.capabilities, vec!["build", "test"]);
    }

    #[test]
    fn test_agent_config_creation() {
        let config = crate::config::AgentConfig::new(
            "config-agent".to_string(),
            "Config Test Agent".to_string()
        );
        
        assert_eq!(config.agent_id, "config-agent");
        assert_eq!(config.name, "Config Test Agent");
        assert!(config.capabilities.is_empty());
        assert_eq!(config.endpoints.registry, None);
        assert_eq!(config.endpoints.router, None);
    }

    #[test]
    fn test_agent_config_with_endpoints() {
        let config = crate::config::AgentConfig::new(
            "endpoint-agent".to_string(),
            "Endpoint Agent".to_string()
        )
        .with_registry_endpoint("http://registry:50051".to_string())
        .with_router_endpoint("http://router:50052".to_string());
        
        assert_eq!(config.endpoints.registry, Some("http://registry:50051".to_string()));
        assert_eq!(config.endpoints.router, Some("http://router:50052".to_string()));
    }

    #[test]
    fn test_agent_config_serialization() {
        let config = crate::config::AgentConfig::new(
            "serialize-agent".to_string(),
            "Serialization Test Agent".to_string()
        )
        .with_capabilities(vec!["serialize".to_string(), "deserialize".to_string()])
        .with_registry_endpoint("http://test:50051".to_string());
        
        // Test JSON serialization
        let json_str = serde_json::to_string(&config).unwrap();
        assert!(json_str.contains("serialize-agent"));
        assert!(json_str.contains("Serialization Test Agent"));
        
        // Test JSON deserialization
        let deserialized: AgentConfig = serde_json::from_str(&json_str).unwrap();
        assert_eq!(deserialized.agent_id, config.agent_id);
        assert_eq!(deserialized.name, config.name);
        assert_eq!(deserialized.capabilities, config.capabilities);
        assert_eq!(deserialized.registry_endpoint, config.registry_endpoint);
    }

    #[test]
    fn test_utility_functions() {
        // Test UUID generation
        let uuid1 = new_uuid();
        let uuid2 = new_uuid();
        
        assert_ne!(uuid1, uuid2);
        assert_eq!(uuid1.len(), 36); // Standard UUID length
        assert!(uuid1.contains('-'));
        
        // Test HLC timestamp
        let timestamp1 = now_hlc_stub();
        std::thread::sleep(std::time::Duration::from_millis(1));
        let timestamp2 = now_hlc_stub();
        
        assert_ne!(timestamp1, timestamp2);
        assert!(timestamp1.parse::<i64>().is_ok());
        assert!(timestamp2.parse::<i64>().unwrap() > timestamp1.parse::<i64>().unwrap());
        
        // Test idempotency token generation
        let token1 = make_idempotency_token("agent1", "send", "hash123");
        let token2 = make_idempotency_token("agent1", "send", "hash456");
        let token3 = make_idempotency_token("agent2", "send", "hash123");
        
        assert_ne!(token1, token2);
        assert_ne!(token1, token3);
        assert_eq!(token1, "agent1:send:hash123");
        assert_eq!(token2, "agent1:send:hash456");
        assert_eq!(token3, "agent2:send:hash123");
    }

    #[test]
    fn test_clone_implementations() {
        // Test SequenceTracker clone
        let tracker1 = SequenceTracker::new(50);
        let tracker2 = tracker1.clone();
        
        // Both should produce different numbers since they have independent state
        let num1 = tracker1.next();
        let num2 = tracker2.next();
        assert_eq!(num1, 50);
        assert_eq!(num2, 50); // Clone maintains the same internal state
        
        // Test PreemptionManager clone
        let mut manager1 = PreemptionManager::new();
        manager1.request_preemption(Some("test".to_string()));
        let manager2 = manager1.clone();
        
        assert!(manager2.is_preemption_requested());
        assert_eq!(manager2.get_preemption_reason(), Some("test".to_string()));
        
        // Test AgentDescriptor clone
        let descriptor1 = AgentDescriptor::new(
            "clone-test".to_string(),
            "Clone Test".to_string()
        );
        let descriptor2 = descriptor1.clone();
        
        assert_eq!(descriptor1.agent_id, descriptor2.agent_id);
        assert_eq!(descriptor1.name, descriptor2.name);
    }

    #[test]
    fn test_debug_implementations() {
        let tracker = SequenceTracker::new(1);
        let debug_str = format!("{:?}", tracker);
        assert!(debug_str.contains("SequenceTracker"));
        
        let manager = PreemptionManager::new();
        let debug_str = format!("{:?}", manager);
        assert!(debug_str.contains("PreemptionManager"));
        
        let descriptor = AgentDescriptor::new("test".to_string(), "Test".to_string());
        let debug_str = format!("{:?}", descriptor);
        assert!(debug_str.contains("AgentDescriptor"));
        assert!(debug_str.contains("test"));
    }
}