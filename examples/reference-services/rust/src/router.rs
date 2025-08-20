use crate::proto::sw4rm::router::{
    router_service_server::{RouterService, RouterServiceServer},
    SendMessageRequest, SendMessageResponse,
    StreamRequest, StreamItem,
};
use crate::proto::sw4rm::common::{Envelope, MessageType};
use dashmap::DashMap;
use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};
use tokio::sync::mpsc;
use tokio_stream::wrappers::UnboundedReceiverStream;
use tonic::{Request, Response, Status};
use tracing::{info, warn, debug};
use uuid::Uuid;

#[derive(Debug, Clone)]
pub struct MessageInfo {
    pub message_id: String,
    pub producer_id: String,
    pub message_type: i32,
    pub content_type: String,
    pub payload_size: usize,
    pub timestamp: u64,
    pub correlation_id: String,
    pub sequence_number: u64,
}

#[derive(Debug)]
pub struct RouterServiceImpl {
    agent_senders: Arc<DashMap<String, mpsc::UnboundedSender<Result<StreamItem, Status>>>>,
    message_log: Arc<DashMap<String, MessageInfo>>,
}

impl RouterServiceImpl {
    pub fn new() -> Self {
        Self {
            agent_senders: Arc::new(DashMap::new()),
            message_log: Arc::new(DashMap::new()),
        }
    }

    pub fn get_status(&self) -> serde_json::Value {
        let active_agents: Vec<String> = self.agent_senders.iter()
            .map(|entry| entry.key().clone())
            .collect();

        serde_json::json!({
            "active_agents": active_agents,
            "total_messages": self.message_log.len(),
            "active_streams": self.agent_senders.len(),
        })
    }

    pub fn get_recent_messages(&self, limit: usize) -> Vec<MessageInfo> {
        let mut messages: Vec<MessageInfo> = self.message_log.iter()
            .map(|entry| entry.value().clone())
            .collect();
        
        messages.sort_by_key(|m| m.timestamp);
        messages.into_iter().rev().take(limit).collect()
    }
}

#[tonic::async_trait]
impl RouterService for RouterServiceImpl {
    async fn send_message(
        &self,
        request: Request<SendMessageRequest>,
    ) -> Result<Response<SendMessageResponse>, Status> {
        let req = request.into_inner();
        let envelope = req.msg.ok_or_else(|| Status::invalid_argument("Message envelope required"))?;
        
        let message_id = if envelope.message_id.is_empty() {
            Uuid::new_v4().to_string()
        } else {
            envelope.message_id.clone()
        };
        
        let producer_id = envelope.producer_id.clone();
        
        let current_time = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_secs();

        // Log the message
        let message_info = MessageInfo {
            message_id: message_id.clone(),
            producer_id: producer_id.clone(),
            message_type: envelope.message_type,
            content_type: envelope.content_type.clone(),
            payload_size: envelope.payload.len(),
            timestamp: current_time,
            correlation_id: envelope.correlation_id.clone(),
            sequence_number: envelope.sequence_number,
        };
        
        self.message_log.insert(message_id.clone(), message_info);

        // Handle ACK messages separately
        if envelope.message_type == MessageType::Acknowledgement as i32 {
            info!("Received ACK message {} from {}", message_id, producer_id);
            return Ok(Response::new(SendMessageResponse {
                accepted: true,
                reason: "ACK message accepted".to_string(),
            }));
        }

        // Route to all agents except sender
        let target_agents: Vec<String> = self.agent_senders.iter()
            .filter_map(|entry| {
                let agent_id = entry.key();
                if agent_id != &producer_id {
                    Some(agent_id.clone())
                } else {
                    None
                }
            })
            .collect();

        let mut delivered_count = 0;
        
        for agent_id in &target_agents {
            if let Some(sender) = self.agent_senders.get(agent_id) {
                let stream_item = StreamItem {
                    msg: Some(envelope.clone()),
                };
                
                if sender.send(Ok(stream_item)).is_ok() {
                    delivered_count += 1;
                    debug!("Routed message {} to {}", message_id, agent_id);
                } else {
                    warn!("Failed to route message {} to {}", message_id, agent_id);
                    // Remove broken sender
                    self.agent_senders.remove(agent_id);
                }
            }
        }

        if delivered_count > 0 {
            info!("Message {} delivered to {} agents", message_id, delivered_count);
            Ok(Response::new(SendMessageResponse {
                accepted: true,
                reason: format!("Message delivered to {} recipients", delivered_count),
            }))
        } else {
            warn!("No recipients found for message {}", message_id);
            Ok(Response::new(SendMessageResponse {
                accepted: false,
                reason: "No recipients available".to_string(),
            }))
        }
    }

    type StreamIncomingStream = UnboundedReceiverStream<Result<StreamItem, Status>>;

    async fn stream_incoming(
        &self,
        request: Request<StreamRequest>,
    ) -> Result<Response<Self::StreamIncomingStream>, Status> {
        let req = request.into_inner();
        let agent_id = req.agent_id;

        info!("Starting message stream for agent: {}", agent_id);

        let (tx, rx) = mpsc::unbounded_channel();
        
        // Store the sender for this agent
        self.agent_senders.insert(agent_id.clone(), tx);

        // Clean up when connection drops
        let agent_senders_clone = Arc::clone(&self.agent_senders);
        let agent_id_clone = agent_id.clone();
        
        // Create the stream first
        let stream = UnboundedReceiverStream::new(rx);
        
        // Cleanup will happen automatically when the stream is dropped
        tokio::spawn(async move {
            tokio::time::sleep(tokio::time::Duration::from_secs(1)).await;
            // This is a simple cleanup - in production you'd want better connection tracking
        });

        Ok(Response::new(stream))
    }
}

pub fn create_service() -> RouterServiceServer<RouterServiceImpl> {
    RouterServiceServer::new(RouterServiceImpl::new())
}