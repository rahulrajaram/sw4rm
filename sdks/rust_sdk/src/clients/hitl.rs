use crate::proto::sw4rm::hitl::hitl_service_client::HitlServiceClient;
use crate::proto::sw4rm::hitl::HitlInvocation;
use crate::{Error, Result};
use tonic::transport::{Channel, Endpoint};

/// Client for interacting with the SW4RM Human-in-the-Loop service
#[derive(Debug, Clone)]
pub struct HitlClient {
    client: HitlServiceClient<Channel>,
}

impl HitlClient {
    /// Create a new HITL client
    pub async fn new(endpoint: &str) -> Result<Self> {
        let channel = Endpoint::from_shared(endpoint.to_string())
            .map_err(|e| Error::Config(format!("Invalid endpoint: {}", e)))?
            .connect()
            .await?;

        Ok(Self {
            client: HitlServiceClient::new(channel),
        })
    }

    /// Send a decision request to human operator
    pub async fn decide(
        &mut self,
        reason_type: i32,
        context: Vec<u8>,
        proposed_actions: Vec<String>,
        priority: i32,
    ) -> Result<HitlDecisionResponse> {
        let invocation = HitlInvocation {
            reason_type,
            context,
            proposed_actions,
            priority,
        };

        let request = tonic::Request::new(invocation);

        let response = self.client.decide(request).await?;
        let decision = response.into_inner();

        Ok(HitlDecisionResponse {
            action: decision.action,
            decision_payload: decision.decision_payload,
            rationale: decision.rationale,
        })
    }
}

/// Response from a HITL decision request
#[derive(Debug, Clone)]
pub struct HitlDecisionResponse {
    pub action: String,
    pub decision_payload: Vec<u8>,
    pub rationale: String,
}