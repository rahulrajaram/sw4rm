use crate::proto::sw4rm::logging::logging_service_client::LoggingServiceClient;
use crate::proto::sw4rm::logging::{LogEvent as ProtoLogEvent, IngestResponse};
use prost_types;
use crate::{Error, Result};
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
        ).with_correlation_id(correlation_id.unwrap_or("").to_string());

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