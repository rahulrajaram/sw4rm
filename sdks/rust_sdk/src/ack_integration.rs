use crate::activity_buffer::PersistentActivityBuffer;
use crate::acks::{build_ack_envelope, map_error_to_error_code};
use crate::clients::RouterClient;
use crate::constants::*;
use crate::envelope::EnvelopeData;
use crate::persistence::PersistentActivityRecord;
use crate::{Error, Result};
use serde_json::Value;
use std::collections::HashMap;
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::sync::RwLock;

/// Result of sending a message with ACK tracking
#[derive(Debug, Clone)]
pub struct SendResult {
    pub success: bool,
    pub message_id: String,
    pub accepted: bool,
    pub reason: String,
    pub activity_record: Option<PersistentActivityRecord>,
}

/// ACK lifecycle manager for message tracking and automatic acknowledgments
pub struct AckLifecycleManager {
    router: Arc<RwLock<RouterClient>>,
    buffer: Arc<PersistentActivityBuffer>,
    agent_id: String,
    auto_ack: bool,
    ack_timeout: Duration,
}

impl AckLifecycleManager {
    pub fn new(
        router: RouterClient,
        buffer: PersistentActivityBuffer,
        agent_id: String,
        auto_ack: bool,
        ack_timeout_seconds: u64,
    ) -> Self {
        Self {
            router: Arc::new(RwLock::new(router)),
            buffer: Arc::new(buffer),
            agent_id,
            auto_ack,
            ack_timeout: Duration::from_secs(ack_timeout_seconds),
        }
    }

    /// Send a message with automatic ACK lifecycle handling
    pub async fn send_message_with_ack(&self, envelope: EnvelopeData) -> Result<SendResult> {
        let message_id = envelope.message_id.clone();

        // Record outgoing message
        let activity_record = self.buffer.record_outgoing(
            serde_json::to_value(&envelope).map_err(Error::Serialization)?
        )?;

        match self._send_message_internal(&envelope).await {
            Ok((accepted, reason)) => {
                // Generate automatic ACK based on result
                if self.auto_ack {
                    let ack_stage = if accepted {
                        ack_stage::FULFILLED
                    } else {
                        ack_stage::REJECTED
                    };
                    
                    let error_code = if accepted {
                        error_code::ERROR_CODE_UNSPECIFIED
                    } else {
                        error_code::VALIDATION_ERROR
                    };

                    // Update activity record via ACK processing
                    let ack_data = serde_json::json!({
                        "ack_for_message_id": message_id,
                        "ack_stage": ack_stage,
                        "error_code": error_code,
                        "note": reason
                    });

                    self.buffer.ack(&ack_data)?;
                    self.buffer.flush()?;
                }

                Ok(SendResult {
                    success: true,
                    message_id,
                    accepted,
                    reason,
                    activity_record: Some(activity_record),
                })
            }
            Err(e) => {
                // Handle send failure
                let error_code = map_error_to_error_code(&e);
                let ack_data = serde_json::json!({
                    "ack_for_message_id": message_id,
                    "ack_stage": ack_stage::FAILED,
                    "error_code": error_code,
                    "note": e.to_string()
                });

                self.buffer.ack(&ack_data)?;
                self.buffer.flush()?;

                Ok(SendResult {
                    success: false,
                    message_id,
                    accepted: false,
                    reason: e.to_string(),
                    activity_record: Some(activity_record),
                })
            }
        }
    }

    async fn _send_message_internal(&self, envelope: &EnvelopeData) -> Result<(bool, String)> {
        let mut router = self.router.write().await;
        
        // Convert our envelope to the format expected by RouterClient
        router.send_message(envelope).await?;
        
        // For now, assume success since RouterClient.send_message doesn't return acceptance info
        // In a real implementation, this would parse the actual router response
        Ok((true, "Message sent successfully".to_string()))
    }

    /// Process an incoming ACK message
    pub fn process_incoming_ack(&self, envelope: &EnvelopeData) -> Result<Option<PersistentActivityRecord>> {
        if envelope.message_type != message_type::ACKNOWLEDGEMENT {
            return Ok(None);
        }

        // Parse ACK from envelope payload
        let ack_data: Value = envelope.json_payload()
            .map_err(|e| Error::InvalidEnvelope(format!("Invalid ACK payload: {}", e)))?;

        // Update activity buffer
        match self.buffer.ack(&ack_data)? {
            Some(record) => {
                self.buffer.flush()?;
                Ok(Some(record))
            }
            None => Ok(None),
        }
    }

    /// Send an ACK message for a received message
    pub async fn send_ack(
        &self,
        ack_for_message_id: String,
        stage: i32,
        error_code: Option<i32>,
        note: Option<String>,
    ) -> Result<SendResult> {
        let ack_envelope = build_ack_envelope(
            self.agent_id.clone(),
            ack_for_message_id,
            stage,
            error_code,
            note,
            None,
            None,
        )?;

        self.send_message_with_ack(ack_envelope).await
    }

    /// Get outgoing messages that need ACK reconciliation
    pub fn get_unacked_outgoing(&self) -> Result<Vec<PersistentActivityRecord>> {
        let unacked = self.buffer.unacked()?;
        let outgoing: Vec<PersistentActivityRecord> = unacked
            .into_iter()
            .filter(|record| record.direction == "out")
            .collect();
        Ok(outgoing)
    }

    /// Get incoming messages that still need ACKs to be sent
    pub fn get_pending_acks(&self) -> Result<Vec<PersistentActivityRecord>> {
        let unacked = self.buffer.unacked()?;
        let pending: Vec<PersistentActivityRecord> = unacked
            .into_iter()
            .filter(|record| {
                record.direction == "in" && 
                matches!(record.ack_stage, 
                    ack_stage::ACK_STAGE_UNSPECIFIED | 
                    ack_stage::RECEIVED
                )
            })
            .collect();
        Ok(pending)
    }

    /// Find messages that may need retry or follow-up ACKs
    pub fn reconcile_acks(&self) -> Result<Vec<PersistentActivityRecord>> {
        let now = chrono::Utc::now().timestamp_millis();
        let timeout_ms = self.ack_timeout.as_millis() as i64;

        let unacked = self.buffer.unacked()?;
        let stale: Vec<PersistentActivityRecord> = unacked
            .into_iter()
            .filter(|record| {
                let age_ms = now - record.ts_ms;
                age_ms > timeout_ms
            })
            .collect();

        Ok(stale)
    }

    /// Automatically send RECEIVED ACK for incoming message
    pub async fn auto_ack_received(&self, envelope: &EnvelopeData) -> Result<SendResult> {
        // Record incoming message
        let envelope_json = serde_json::to_value(envelope).map_err(Error::Serialization)?;
        self.buffer.record_incoming(envelope_json)?;

        // Send RECEIVED ACK
        self.send_ack(
            envelope.message_id.clone(),
            ack_stage::RECEIVED,
            None,
            None,
        ).await
    }

    /// Send READ ACK to indicate message has been processed
    pub async fn auto_ack_read(&self, message_id: String) -> Result<SendResult> {
        self.send_ack(message_id, ack_stage::READ, None, None).await
    }

    /// Send FULFILLED ACK to indicate successful processing
    pub async fn auto_ack_fulfilled(&self, message_id: String, note: Option<String>) -> Result<SendResult> {
        self.send_ack(message_id, ack_stage::FULFILLED, None, note).await
    }

    /// Send REJECTED ACK to indicate processing rejection
    pub async fn auto_ack_rejected(
        &self,
        message_id: String,
        reason: String,
        error_code: Option<i32>,
    ) -> Result<SendResult> {
        let code = error_code.unwrap_or(error_code::VALIDATION_ERROR);
        self.send_ack(message_id, ack_stage::REJECTED, Some(code), Some(reason)).await
    }

    /// Send FAILED ACK to indicate processing failure
    pub async fn auto_ack_failed(&self, message_id: String, error: &Error) -> Result<SendResult> {
        let error_code = map_error_to_error_code(error);
        self.send_ack(
            message_id,
            ack_stage::FAILED,
            Some(error_code),
            Some(error.to_string()),
        ).await
    }
}

/// High-level message processor with automatic ACK handling
pub struct MessageProcessor {
    ack_manager: AckLifecycleManager,
    message_handlers: HashMap<i32, Box<dyn Fn(&EnvelopeData) -> Result<Value> + Send + Sync>>,
    default_handler: Option<Box<dyn Fn(&EnvelopeData) -> Result<Value> + Send + Sync>>,
}

impl MessageProcessor {
    pub fn new(ack_manager: AckLifecycleManager) -> Self {
        Self {
            ack_manager,
            message_handlers: HashMap::new(),
            default_handler: None,
        }
    }

    /// Register a handler for a specific message type
    pub fn register_handler<F>(&mut self, message_type: i32, handler: F)
    where
        F: Fn(&EnvelopeData) -> Result<Value> + Send + Sync + 'static,
    {
        self.message_handlers.insert(message_type, Box::new(handler));
    }

    /// Set a default handler for unregistered message types
    pub fn set_default_handler<F>(&mut self, handler: F)
    where
        F: Fn(&EnvelopeData) -> Result<Value> + Send + Sync + 'static,
    {
        self.default_handler = Some(Box::new(handler));
    }

    /// Process an incoming message with automatic ACK handling
    pub async fn process_message(&self, envelope: &EnvelopeData) -> Result<SendResult> {
        let message_type = envelope.message_type;
        let message_id = envelope.message_id.clone();

        // Send RECEIVED ACK immediately
        self.ack_manager.auto_ack_received(envelope).await?;

        // Handle ACK messages specially
        if message_type == message_type::ACKNOWLEDGEMENT {
            self.ack_manager.process_incoming_ack(envelope)?;
            return Ok(SendResult {
                success: true,
                message_id,
                accepted: true,
                reason: "ACK processed".to_string(),
                activity_record: None,
            });
        }

        // Send READ ACK before processing
        self.ack_manager.auto_ack_read(message_id.clone()).await?;

        // Find and execute handler
        let handler_result = if let Some(handler) = self.message_handlers.get(&message_type) {
            handler(envelope)
        } else if let Some(default_handler) = &self.default_handler {
            default_handler(envelope)
        } else {
            return self.ack_manager.auto_ack_rejected(
                message_id,
                format!("No handler for message type {}", message_type),
                Some(error_code::UNSUPPORTED_MESSAGE_TYPE),
            ).await;
        };

        match handler_result {
            Ok(_result) => {
                // Send FULFILLED ACK on successful processing
                self.ack_manager.auto_ack_fulfilled(
                    message_id,
                    Some("Processed successfully".to_string()),
                ).await
            }
            Err(e) => {
                // Send FAILED ACK on processing error
                self.ack_manager.auto_ack_failed(message_id, &e).await
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::persistence::JsonFilePersistence;
    use tempfile::NamedTempFile;

    #[tokio::test]
    async fn test_ack_lifecycle_manager() {
        let temp_file = NamedTempFile::new().unwrap();
        let persistence = Box::new(JsonFilePersistence::new(temp_file.path()));
        let buffer = PersistentActivityBuffer::new(1000, Some(persistence)).unwrap();
        
        // Note: We can't easily test with a real RouterClient without a running server
        // This is a placeholder for the pattern
        // let router = RouterClient::new("http://localhost:50052").await.unwrap();
        // let manager = AckLifecycleManager::new(router, buffer, "test-agent".to_string(), true, 30);
    }
}