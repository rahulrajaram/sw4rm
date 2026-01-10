use crate::proto::sw4rm::logging::logging_service_client::LoggingServiceClient;
use crate::proto::sw4rm::logging::{IngestResponse, LogEvent as ProtoLogEvent};
use crate::{Error, Result};
use prost_types;
use tonic::transport::{Channel, Endpoint};

/// Client for interacting with the SW4RM Logging service
#[derive(Debug, Clone)]
pub struct LoggingClient {
    client: LoggingServiceClient<Channel>,
}

impl LoggingClient {
    /// Create a new logging client
    pub async fn new(endpoint: &str) -> Result<Self> {
        let channel = Endpoint::from_shared(endpoint.to_string())
            .map_err(|e| Error::Config(format!("Invalid endpoint: {}", e)))?
            .connect()
            .await?;

        Ok(Self {
            client: LoggingServiceClient::new(channel),
        })
    }

    /// Ingest a single log event
    pub async fn ingest(&mut self, event: LogEvent) -> Result<IngestResponse> {
        let ts = event.ts.map(|t| prost_types::Timestamp {
            seconds: t.timestamp(),
            nanos: t.timestamp_subsec_nanos() as i32,
        });

        let proto_event = ProtoLogEvent {
            ts,
            correlation_id: event.correlation_id,
            agent_id: event.agent_id,
            event_type: event.event_type,
            level: event.level,
            details_json: event.details_json,
        };

        let request = tonic::Request::new(proto_event);
        let response = self.client.ingest(request).await?;
        Ok(response.into_inner())
    }

    /// Log a single event (convenience method)
    pub async fn log(
        &mut self,
        agent_id: &str,
        event_type: &str,
        level: &str,
        details_json: &str,
        correlation_id: Option<&str>,
    ) -> Result<IngestResponse> {
        let event = LogEvent::new(
            agent_id.to_string(),
            event_type.to_string(),
            level.to_string(),
            details_json.to_string(),
        )
        .with_correlation_id(correlation_id.unwrap_or("").to_string());

        self.ingest(event).await
    }
}

/// Log event structure
#[derive(Debug, Clone)]
pub struct LogEvent {
    pub ts: Option<chrono::DateTime<chrono::Utc>>,
    pub correlation_id: String,
    pub agent_id: String,
    pub event_type: String,
    pub level: String,
    pub details_json: String,
}

impl LogEvent {
    pub fn new(agent_id: String, event_type: String, level: String, details_json: String) -> Self {
        Self {
            ts: Some(chrono::Utc::now()),
            correlation_id: String::new(),
            agent_id,
            event_type,
            level,
            details_json,
        }
    }

    pub fn with_timestamp(mut self, ts: chrono::DateTime<chrono::Utc>) -> Self {
        self.ts = Some(ts);
        self
    }

    pub fn with_correlation_id(mut self, correlation_id: String) -> Self {
        self.correlation_id = correlation_id;
        self
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Test LogEvent construction with new()
    #[test]
    fn test_log_event_new() {
        let event = LogEvent::new(
            "agent-1".to_string(),
            "task_started".to_string(),
            "INFO".to_string(),
            r#"{"task_id": "task-1"}"#.to_string(),
        );

        assert_eq!(event.agent_id, "agent-1");
        assert_eq!(event.event_type, "task_started");
        assert_eq!(event.level, "INFO");
        assert!(event.ts.is_some());
        assert!(event.correlation_id.is_empty());
    }

    /// Test LogEvent with_timestamp builder
    #[test]
    fn test_log_event_with_timestamp() {
        let ts = chrono::Utc::now();
        let event = LogEvent::new(
            "agent-1".to_string(),
            "event".to_string(),
            "INFO".to_string(),
            "{}".to_string(),
        )
        .with_timestamp(ts);

        assert_eq!(event.ts, Some(ts));
    }

    /// Test LogEvent with_correlation_id builder
    #[test]
    fn test_log_event_with_correlation_id() {
        let event = LogEvent::new(
            "agent-1".to_string(),
            "event".to_string(),
            "INFO".to_string(),
            "{}".to_string(),
        )
        .with_correlation_id("corr-123".to_string());

        assert_eq!(event.correlation_id, "corr-123");
    }

    /// Test LogEvent with all fields
    #[test]
    fn test_log_event_all_fields() {
        let ts = chrono::Utc::now();
        let event = LogEvent::new(
            "agent-1".to_string(),
            "task_completed".to_string(),
            "INFO".to_string(),
            r#"{"task_id": "task-1", "duration_ms": 5000}"#.to_string(),
        )
        .with_timestamp(ts)
        .with_correlation_id("corr-456".to_string());

        assert_eq!(event.agent_id, "agent-1");
        assert_eq!(event.event_type, "task_completed");
        assert_eq!(event.level, "INFO");
        assert_eq!(event.ts, Some(ts));
        assert_eq!(event.correlation_id, "corr-456");
    }

    /// Test LogEvent clone
    #[test]
    fn test_log_event_clone() {
        let event = LogEvent::new(
            "agent-1".to_string(),
            "event".to_string(),
            "INFO".to_string(),
            "{}".to_string(),
        )
        .with_correlation_id("corr-1".to_string());

        let cloned = event.clone();
        assert_eq!(event.agent_id, cloned.agent_id);
        assert_eq!(event.correlation_id, cloned.correlation_id);
    }

    /// Test LogEvent debug
    #[test]
    fn test_log_event_debug() {
        let event = LogEvent::new(
            "agent-1".to_string(),
            "test_event".to_string(),
            "DEBUG".to_string(),
            "{}".to_string(),
        );

        let debug_str = format!("{:?}", event);
        assert!(debug_str.contains("LogEvent"));
        assert!(debug_str.contains("agent-1"));
        assert!(debug_str.contains("test_event"));
    }

    /// Test different log levels
    #[test]
    fn test_different_log_levels() {
        let levels = vec!["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"];

        for level in levels {
            let event = LogEvent::new(
                "agent-1".to_string(),
                "test".to_string(),
                level.to_string(),
                "{}".to_string(),
            );
            assert_eq!(event.level, level);
        }
    }

    /// Test error event with structured metadata
    #[test]
    fn test_error_event() {
        let details = serde_json::json!({
            "error_code": "TASK_TIMEOUT",
            "stack_trace": "...",
            "task_id": "task-1"
        });

        let event = LogEvent::new(
            "agent-1".to_string(),
            "task_failed".to_string(),
            "ERROR".to_string(),
            details.to_string(),
        );

        assert_eq!(event.level, "ERROR");
        assert!(event.details_json.contains("TASK_TIMEOUT"));
    }

    /// Test ProtoLogEvent conversion
    #[test]
    fn test_proto_log_event_conversion() {
        let ts = chrono::Utc::now();
        let event = LogEvent::new(
            "agent-1".to_string(),
            "test_event".to_string(),
            "INFO".to_string(),
            r#"{"key": "value"}"#.to_string(),
        )
        .with_timestamp(ts)
        .with_correlation_id("corr-1".to_string());

        // Simulate conversion to proto
        let proto_ts = event.ts.map(|t| prost_types::Timestamp {
            seconds: t.timestamp(),
            nanos: t.timestamp_subsec_nanos() as i32,
        });

        let proto_event = ProtoLogEvent {
            ts: proto_ts,
            correlation_id: event.correlation_id.clone(),
            agent_id: event.agent_id.clone(),
            event_type: event.event_type.clone(),
            level: event.level.clone(),
            details_json: event.details_json.clone(),
        };

        assert_eq!(proto_event.agent_id, "agent-1");
        assert_eq!(proto_event.event_type, "test_event");
        assert_eq!(proto_event.level, "INFO");
        assert!(proto_event.ts.is_some());
    }

    /// Test multiple log events
    #[test]
    fn test_multiple_log_events() {
        let events: Vec<LogEvent> = (0..5)
            .map(|i| {
                LogEvent::new(
                    "agent-1".to_string(),
                    format!("event_{}", i),
                    "INFO".to_string(),
                    format!(r#"{{"index": {}}}"#, i),
                )
            })
            .collect();

        assert_eq!(events.len(), 5);
        assert_eq!(events[0].event_type, "event_0");
        assert_eq!(events[4].event_type, "event_4");
    }

    /// Test log event lifecycle for task
    #[test]
    fn test_task_lifecycle_events() {
        let correlation_id = "corr-task-1";

        // Task started
        let started = LogEvent::new(
            "agent-1".to_string(),
            "task_started".to_string(),
            "INFO".to_string(),
            r#"{"task_id": "task-1", "event_type": "started"}"#.to_string(),
        )
        .with_correlation_id(correlation_id.to_string());

        // Task progress
        let progress = LogEvent::new(
            "agent-1".to_string(),
            "task_progress".to_string(),
            "INFO".to_string(),
            r#"{"task_id": "task-1", "percent": 50}"#.to_string(),
        )
        .with_correlation_id(correlation_id.to_string());

        // Task completed
        let completed = LogEvent::new(
            "agent-1".to_string(),
            "task_completed".to_string(),
            "INFO".to_string(),
            r#"{"task_id": "task-1", "event_type": "completed"}"#.to_string(),
        )
        .with_correlation_id(correlation_id.to_string());

        assert_eq!(started.correlation_id, correlation_id);
        assert_eq!(progress.correlation_id, correlation_id);
        assert_eq!(completed.correlation_id, correlation_id);
    }

    /// Test concurrent agent logging
    #[test]
    fn test_concurrent_agent_events() {
        let agent_ids = vec!["agent-1", "agent-2", "agent-3"];

        let events: Vec<LogEvent> = agent_ids
            .into_iter()
            .enumerate()
            .map(|(i, agent_id)| {
                LogEvent::new(
                    agent_id.to_string(),
                    "log_event".to_string(),
                    "INFO".to_string(),
                    format!(r#"{{"message": "Log from {}"}}"#, agent_id),
                )
                .with_correlation_id(format!("corr-{}", i))
            })
            .collect();

        assert_eq!(events.len(), 3);
        assert_eq!(events[0].agent_id, "agent-1");
        assert_eq!(events[1].agent_id, "agent-2");
        assert_eq!(events[2].agent_id, "agent-3");
    }

    /// Test empty details_json
    #[test]
    fn test_empty_details() {
        let event = LogEvent::new(
            "agent-1".to_string(),
            "simple_event".to_string(),
            "INFO".to_string(),
            String::new(),
        );

        assert!(event.details_json.is_empty());
    }

    /// Test complex JSON details
    #[test]
    fn test_complex_details() {
        let details = serde_json::json!({
            "task_id": "task-1",
            "duration_ms": 5000,
            "success": true,
            "output": {"result": "completed"},
            "tags": ["production", "critical"]
        });

        let event = LogEvent::new(
            "agent-1".to_string(),
            "task_completed".to_string(),
            "INFO".to_string(),
            details.to_string(),
        );

        // Verify JSON can be parsed back
        let parsed: serde_json::Value = serde_json::from_str(&event.details_json).unwrap();
        assert_eq!(parsed["task_id"], "task-1");
        assert_eq!(parsed["duration_ms"], 5000);
        assert_eq!(parsed["success"], true);
    }
}
