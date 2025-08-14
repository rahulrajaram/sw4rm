use crate::proto::sw4rm::reasoning::reasoning_proxy_client::ReasoningProxyClient;
use crate::proto::sw4rm::reasoning::{
    ParallelismCheckRequest, ParallelismCheckResponse as ProtoParallelismResponse,
    DebateEvaluateRequest, DebateEvaluateResponse as ProtoDebateResponse,
    SummarizeRequest, SummarizeResponse, TextSegment
};
use crate::{Error, Result};
use tonic::transport::{Channel, Endpoint};

/// Client for interacting with the SW4RM Reasoning service
#[derive(Debug, Clone)]
pub struct ReasoningClient {
    client: ReasoningProxyClient<Channel>,
}

impl ReasoningClient {
    /// Create a new reasoning client
    pub async fn new(endpoint: &str) -> Result<Self> {
        let channel = Endpoint::from_shared(endpoint.to_string())
            .map_err(|e| Error::Config(format!("Invalid endpoint: {}", e)))?
            .connect()
            .await?;

        Ok(Self {
            client: ReasoningProxyClient::new(channel),
        })
    }

    /// Check if two scopes can be executed in parallel
    pub async fn check_parallelism(
        &mut self,
        scope_a: &str,
        scope_b: &str,
    ) -> Result<ParallelismCheckResponse> {
        let request = tonic::Request::new(ParallelismCheckRequest {
            scope_a: scope_a.to_string(),
            scope_b: scope_b.to_string(),
        });

        let response = self.client.check_parallelism(request).await?;
        let inner = response.into_inner();

        Ok(ParallelismCheckResponse {
            confidence_score: inner.confidence_score,
            notes: inner.notes,
        })
    }

    /// Summarize a sequence of text segments with a token budget
    pub async fn summarize(
        &mut self,
        session_id: &str,
        segments: Vec<(String, String, i64, String)>, // (kind, content, seq, at)
        max_tokens: u32,
        mode: &str,
) -> Result<RemoteSummary> {
        let request = tonic::Request::new(SummarizeRequest {
            session_id: session_id.to_string(),
            segments: segments
                .into_iter()
                .map(|(kind, content, seq, at)| TextSegment { kind, content, seq, at })
                .collect(),
            max_tokens,
            mode: mode.to_string(),
        });
        let response = self.client.summarize(request).await?;
        let inner = response.into_inner();
        Ok(RemoteSummary {
            summary: inner.summary,
            tokens: inner.tokens,
            cost_cents: inner.cost_cents,
            model: inner.model,
        })
    }

    /// Evaluate a debate between two proposals
    pub async fn evaluate_debate(
        &mut self,
        negotiation_id: &str,
        proposal_a: &str,
        proposal_b: &str,
        intensity: &str,
    ) -> Result<DebateEvaluationResponse> {
        let request = tonic::Request::new(DebateEvaluateRequest {
            negotiation_id: negotiation_id.to_string(),
            proposal_a: proposal_a.to_string(),
            proposal_b: proposal_b.to_string(),
            intensity: intensity.to_string(),
        });

        let response = self.client.evaluate_debate(request).await?;
        let inner = response.into_inner();

        Ok(DebateEvaluationResponse {
            confidence_score: inner.confidence_score,
            notes: inner.notes,
        })
    }
}

/// Response from parallelism check
#[derive(Debug, Clone)]
pub struct ParallelismCheckResponse {
    pub confidence_score: f64,
    pub notes: String,
}

/// Response from debate evaluation
#[derive(Debug, Clone)]
pub struct DebateEvaluationResponse {
    pub confidence_score: f64,
    pub notes: String,
}
#[derive(Debug, Clone)]
pub struct RemoteSummary {
    pub summary: String,
    pub tokens: u32,
    pub cost_cents: f64,
    pub model: String,
}
