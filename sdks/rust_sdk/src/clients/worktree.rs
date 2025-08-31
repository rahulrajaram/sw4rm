use crate::proto::sw4rm::worktree::worktree_service_client::WorktreeServiceClient;
use crate::proto::sw4rm::worktree::{BindRequest, StatusRequest, SwitchRequest, UnbindRequest};
use crate::{Error, Result};
use tonic::transport::{Channel, Endpoint};

/// Client for interacting with the SW4RM Worktree service
#[derive(Debug, Clone)]
pub struct WorktreeClient {
    client: WorktreeServiceClient<Channel>,
}

impl WorktreeClient {
    /// Create a new worktree client
    pub async fn new(endpoint: &str) -> Result<Self> {
        let channel = Endpoint::from_shared(endpoint.to_string())
            .map_err(|e| Error::Config(format!("Invalid endpoint: {}", e)))?
            .connect()
            .await?;

        Ok(Self {
            client: WorktreeServiceClient::new(channel),
        })
    }

    /// Bind an agent to a worktree
    pub async fn bind_worktree(
        &mut self,
        agent_id: &str,
        repo_id: &str,
        worktree_id: &str,
    ) -> Result<()> {
        let request = tonic::Request::new(BindRequest {
            agent_id: agent_id.to_string(),
            repo_id: repo_id.to_string(),
            worktree_id: worktree_id.to_string(),
        });

        self.client.bind(request).await?;
        Ok(())
    }

    /// Unbind an agent from a worktree
    pub async fn unbind_worktree(&mut self, agent_id: &str, _worktree_id: &str) -> Result<()> {
        let request = tonic::Request::new(UnbindRequest {
            agent_id: agent_id.to_string(),
        });

        self.client.unbind(request).await?;
        Ok(())
    }

    /// Switch to a different worktree
    pub async fn switch_worktree(
        &mut self,
        agent_id: &str,
        _from_worktree_id: &str,
        to_worktree_id: &str,
    ) -> Result<()> {
        let request = tonic::Request::new(SwitchRequest {
            agent_id: agent_id.to_string(),
            target_worktree_id: to_worktree_id.to_string(),
            requires_hitl: false,
        });

        self.client.request_switch(request).await?;
        Ok(())
    }

    /// Get worktree status for an agent
    pub async fn worktree_status(&mut self, agent_id: &str) -> Result<WorktreeStatusResponse> {
        let request = tonic::Request::new(StatusRequest {
            agent_id: agent_id.to_string(),
        });

        let response = self.client.status(request).await?;
        let inner = response.into_inner();

        Ok(WorktreeStatusResponse {
            agent_id: agent_id.to_string(),
            repo_id: inner.repo_id,
            worktree_id: inner.worktree_id,
            state: inner.state,
        })
    }
}

/// Response from worktree status request
#[derive(Debug, Clone)]
pub struct WorktreeStatusResponse {
    pub agent_id: String,
    pub repo_id: String,
    pub worktree_id: String,
    pub state: String,
}
