use crate::envelope::EnvelopeData;
use crate::proto::sw4rm::common::Envelope as ProtoEnvelope;
use crate::proto::sw4rm::router::router_service_client::RouterServiceClient;
use crate::proto::sw4rm::router::{SendMessageRequest, StreamRequest};
use crate::{Error, Result};
use async_trait::async_trait;
use std::pin::Pin;
use tokio_stream::Stream;
use tonic::transport::{Channel, Endpoint};
use tracing::{debug, error, info, warn};

/// Response from sending a message
#[derive(Debug, Clone)]
pub struct SendResult {
    pub accepted: bool,
    pub reason: String,
}

/// Minimal trait abstraction to allow testing and decouple ACK logic from the concrete client
#[async_trait]
pub trait RouterLike: Send + Sync {
    async fn route_send(&mut self, envelope: &EnvelopeData) -> Result<SendResult>;
}

/// Client for interacting with the SW4RM Router service
#[derive(Debug, Clone)]
pub struct RouterClient {
    client: RouterServiceClient<Channel>,
    endpoint: String,
}

impl RouterClient {
    /// Create a new router client
    pub async fn new(endpoint: &str) -> Result<Self> {
        debug!("Creating router client for endpoint: {}", endpoint);

        let channel = Endpoint::from_shared(endpoint.to_string())
            .map_err(|e| Error::Config(format!("Invalid router endpoint: {}", e)))?
            .connect()
            .await
            .map_err(|e| {
                error!("Failed to connect to router at {}: {}", endpoint, e);
                Error::Connection(format!("Router connection failed: {}", e))
            })?;

        info!("Successfully connected to router at {}", endpoint);

        Ok(Self {
            client: RouterServiceClient::new(channel),
            endpoint: endpoint.to_string(),
        })
    }

    /// Create a router client with an existing channel (for testing)
    pub fn with_channel(channel: Channel, endpoint: String) -> Self {
        Self {
            client: RouterServiceClient::new(channel),
            endpoint,
        }
    }

    /// Send a message through the router
    pub async fn send_message(&mut self, envelope: &EnvelopeData) -> Result<SendResult> {
        debug!(
            "Sending message {} from {} (type: {})",
            envelope.message_id, envelope.producer_id, envelope.message_type
        );

        let proto_envelope = ProtoEnvelope {
            message_id: envelope.message_id.clone(),
            idempotency_token: envelope.idempotency_token.clone(),
            producer_id: envelope.producer_id.clone(),
            correlation_id: envelope.correlation_id.clone(),
            sequence_number: envelope.sequence_number,
            retry_count: envelope.retry_count,
            message_type: envelope.message_type,
            content_type: envelope.content_type.clone(),
            content_length: envelope.content_length,
            repo_id: envelope.repo_id.clone(),
            worktree_id: envelope.worktree_id.clone(),
            hlc_timestamp: envelope.hlc_timestamp.clone(),
            ttl_ms: envelope.ttl_ms,
            timestamp: None, // Set by router
            payload: envelope.payload.clone(),
        };

        let request = tonic::Request::new(SendMessageRequest {
            msg: Some(proto_envelope),
        });

        match self.client.send_message(request).await {
            Ok(response) => {
                let inner = response.into_inner();
                let result = SendResult {
                    accepted: inner.accepted,
                    reason: inner.reason.clone(),
                };

                if inner.accepted {
                    debug!("Message {} accepted by router", envelope.message_id);
                } else {
                    warn!(
                        "Message {} rejected by router: {}",
                        envelope.message_id, inner.reason
                    );
                }

                Ok(result)
            }
            Err(status) => {
                error!("Failed to send message {}: {}", envelope.message_id, status);
                Err(Error::Status(status))
            }
        }
    }

    /// Stream incoming messages for an agent
    pub async fn stream_incoming(
        &mut self,
        agent_id: &str,
    ) -> Result<Pin<Box<dyn Stream<Item = Result<EnvelopeData>> + Send>>> {
        info!("Starting message stream for agent: {}", agent_id);

        let request = tonic::Request::new(StreamRequest {
            agent_id: agent_id.to_string(),
        });

        let response = self.client.stream_incoming(request).await.map_err(|e| {
            error!("Failed to start stream for agent {}: {}", agent_id, e);
            Error::Status(e)
        })?;

        let stream = response.into_inner();
        debug!("Message stream established for agent: {}", agent_id);

        let mapped_stream = tokio_stream::StreamExt::map(stream, |result| match result {
            Ok(stream_item) => {
                if let Some(envelope) = stream_item.msg {
                    debug!("Received message {} for agent", envelope.message_id);

                    Ok(EnvelopeData {
                        message_id: envelope.message_id,
                        idempotency_token: envelope.idempotency_token,
                        producer_id: envelope.producer_id,
                        correlation_id: envelope.correlation_id,
                        sequence_number: envelope.sequence_number,
                        retry_count: envelope.retry_count,
                        message_type: envelope.message_type,
                        content_type: envelope.content_type,
                        content_length: envelope.content_length,
                        repo_id: envelope.repo_id,
                        worktree_id: envelope.worktree_id,
                        hlc_timestamp: envelope.hlc_timestamp,
                        ttl_ms: envelope.ttl_ms,
                        payload: envelope.payload,
                    })
                } else {
                    error!("Received stream item without envelope");
                    Err(Error::Protocol(
                        "Missing envelope in stream item".to_string(),
                    ))
                }
            }
            Err(status) => {
                warn!("Stream error: {}", status);
                Err(Error::Status(status))
            }
        });

        Ok(Box::pin(mapped_stream))
    }

    /// Get the endpoint this client is connected to
    pub fn endpoint(&self) -> &str {
        &self.endpoint
    }

    /// Check router health by attempting to send a ping message
    pub async fn health_check(&mut self) -> Result<bool> {
        debug!("Performing health check for router client");

        use crate::constants;
        use crate::envelope::EnvelopeBuilder;

        // Create a minimal ping message
        let ping_envelope = EnvelopeBuilder::new(
            "health-check".to_string(),
            constants::message_type::HEARTBEAT,
        )
        .with_json_payload(&serde_json::json!({"ping": "health-check"}))
        .map_err(|e| Error::Internal(format!("Failed to create health check message: {}", e)))?
        .build();

        match self.send_message(&ping_envelope).await {
            Ok(result) => {
                debug!(
                    "Router health check result: accepted={}, reason={}",
                    result.accepted, result.reason
                );
                Ok(true)
            }
            Err(Error::Status(status)) => {
                // Some errors are expected for health checks
                match status.code() {
                    tonic::Code::NotFound | tonic::Code::InvalidArgument => Ok(true),
                    _ => {
                        error!("Router health check failed: {}", status);
                        Ok(false)
                    }
                }
            }
            Err(e) => {
                error!("Router health check error: {}", e);
                Err(e)
            }
        }
    }
}

#[async_trait]
impl RouterLike for RouterClient {
    async fn route_send(&mut self, envelope: &EnvelopeData) -> Result<SendResult> {
        Self::send_message(self, envelope).await
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::constants;
    use crate::envelope::EnvelopeBuilder;

    #[tokio::test(flavor = "current_thread")]
    async fn test_router_client_creation() {
        let endpoint = "http://localhost:50052";
        let channel = Endpoint::from_static("http://localhost:50052").connect_lazy();
        let client = RouterClient::with_channel(channel, endpoint.to_string());

        assert_eq!(client.endpoint(), endpoint);
    }

    #[test]
    fn test_envelope_conversion() {
        let envelope =
            EnvelopeBuilder::new("test-producer".to_string(), constants::message_type::DATA)
                .with_payload(b"test data".to_vec())
                .build();

        // Test conversion to proto format
        let proto_envelope = ProtoEnvelope {
            message_id: envelope.message_id.clone(),
            idempotency_token: envelope.idempotency_token.clone(),
            producer_id: envelope.producer_id.clone(),
            correlation_id: envelope.correlation_id.clone(),
            sequence_number: envelope.sequence_number,
            retry_count: envelope.retry_count,
            message_type: envelope.message_type,
            content_type: envelope.content_type.clone(),
            content_length: envelope.content_length,
            repo_id: envelope.repo_id.clone(),
            worktree_id: envelope.worktree_id.clone(),
            hlc_timestamp: envelope.hlc_timestamp.clone(),
            ttl_ms: envelope.ttl_ms,
            timestamp: None,
            payload: envelope.payload.clone(),
        };

        assert_eq!(proto_envelope.producer_id, "test-producer");
        assert_eq!(proto_envelope.message_type, constants::message_type::DATA);
        assert_eq!(proto_envelope.payload, b"test data");
    }

    #[test]
    fn test_send_result() {
        let result = SendResult {
            accepted: true,
            reason: "Message accepted".to_string(),
        };

        assert!(result.accepted);
        assert_eq!(result.reason, "Message accepted");
    }
}
