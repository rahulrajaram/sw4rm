use crate::proto::sw4rm::common::DebateIntensity;
use crate::proto::sw4rm::negotiation::negotiation_service_client::NegotiationServiceClient;
use crate::proto::sw4rm::negotiation::{
    AbortRequest, CounterProposal, Decision, Evaluation, NegotiationOpen, Proposal,
};
use crate::{Error, Result};
use prost_types;
use tonic::transport::{Channel, Endpoint};

/// Client for interacting with the SW4RM Negotiation service
#[derive(Debug, Clone)]
pub struct NegotiationClient {
    client: NegotiationServiceClient<Channel>,
}

impl NegotiationClient {
    /// Create a new negotiation client
    pub async fn new(endpoint: &str) -> Result<Self> {
        let channel = Endpoint::from_shared(endpoint.to_string())
            .map_err(|e| Error::Config(format!("Invalid endpoint: {}", e)))?
            .connect()
            .await?;

        Ok(Self {
            client: NegotiationServiceClient::new(channel),
        })
    }

    /// Open a new negotiation session
    pub async fn open(
        &mut self,
        negotiation_id: &str,
        correlation_id: &str,
        topic: &str,
        participants: Vec<String>,
        intensity: DebateIntensity,
        debate_timeout: Option<std::time::Duration>,
    ) -> Result<()> {
        let debate_timeout = debate_timeout.map(|t| prost_types::Duration {
            seconds: t.as_secs() as i64,
            nanos: t.subsec_nanos() as i32,
        });

        let request = tonic::Request::new(NegotiationOpen {
            negotiation_id: negotiation_id.to_string(),
            correlation_id: correlation_id.to_string(),
            topic: topic.to_string(),
            participants,
            intensity: intensity as i32,
            debate_timeout,
        });

        self.client.open(request).await?;
        Ok(())
    }

    /// Make a proposal in a negotiation
    pub async fn propose(
        &mut self,
        negotiation_id: &str,
        from_agent: &str,
        content_type: &str,
        payload: Vec<u8>,
    ) -> Result<()> {
        let request = tonic::Request::new(Proposal {
            negotiation_id: negotiation_id.to_string(),
            from_agent: from_agent.to_string(),
            content_type: content_type.to_string(),
            payload,
        });

        self.client.propose(request).await?;
        Ok(())
    }

    /// Make a counter-proposal
    pub async fn counter(
        &mut self,
        negotiation_id: &str,
        from_agent: &str,
        content_type: &str,
        payload: Vec<u8>,
    ) -> Result<()> {
        let request = tonic::Request::new(CounterProposal {
            negotiation_id: negotiation_id.to_string(),
            from_agent: from_agent.to_string(),
            content_type: content_type.to_string(),
            payload,
        });

        self.client.counter(request).await?;
        Ok(())
    }

    /// Evaluate a proposal
    pub async fn evaluate(
        &mut self,
        negotiation_id: &str,
        from_agent: &str,
        confidence_score: f64,
        notes: &str,
    ) -> Result<()> {
        let request = tonic::Request::new(Evaluation {
            negotiation_id: negotiation_id.to_string(),
            from_agent: from_agent.to_string(),
            confidence_score,
            notes: notes.to_string(),
        });

        self.client.evaluate(request).await?;
        Ok(())
    }

    /// Make a decision on a negotiation
    pub async fn decide(
        &mut self,
        negotiation_id: &str,
        decided_by: &str,
        content_type: &str,
        result: Vec<u8>,
    ) -> Result<()> {
        let request = tonic::Request::new(Decision {
            negotiation_id: negotiation_id.to_string(),
            decided_by: decided_by.to_string(),
            content_type: content_type.to_string(),
            result,
        });

        self.client.decide(request).await?;
        Ok(())
    }

    /// Abort a negotiation
    pub async fn abort(&mut self, negotiation_id: &str, reason: &str) -> Result<()> {
        let request = tonic::Request::new(AbortRequest {
            negotiation_id: negotiation_id.to_string(),
            reason: reason.to_string(),
        });

        self.client.abort(request).await?;
        Ok(())
    }
}
