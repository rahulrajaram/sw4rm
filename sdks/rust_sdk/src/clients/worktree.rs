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

#[cfg(test)]
mod tests {
    use super::*;

    /// Test BindRequest construction
    #[test]
    fn test_bind_request_construction() {
        let request = BindRequest {
            agent_id: "agent-1".to_string(),
            repo_id: "repo-1".to_string(),
            worktree_id: "worktree-1".to_string(),
        };

        assert_eq!(request.agent_id, "agent-1");
        assert_eq!(request.repo_id, "repo-1");
        assert_eq!(request.worktree_id, "worktree-1");
    }

    /// Test UnbindRequest construction
    #[test]
    fn test_unbind_request_construction() {
        let request = UnbindRequest {
            agent_id: "agent-1".to_string(),
        };

        assert_eq!(request.agent_id, "agent-1");
    }

    /// Test StatusRequest construction
    #[test]
    fn test_status_request_construction() {
        let request = StatusRequest {
            agent_id: "agent-1".to_string(),
        };

        assert_eq!(request.agent_id, "agent-1");
    }

    /// Test SwitchRequest with all parameters
    #[test]
    fn test_switch_request_all_params() {
        let request = SwitchRequest {
            agent_id: "agent-1".to_string(),
            target_worktree_id: "worktree-2".to_string(),
            requires_hitl: true,
        };

        assert_eq!(request.agent_id, "agent-1");
        assert_eq!(request.target_worktree_id, "worktree-2");
        assert!(request.requires_hitl);
    }

    /// Test SwitchRequest with default requires_hitl (false)
    #[test]
    fn test_switch_request_default_hitl() {
        let request = SwitchRequest {
            agent_id: "agent-1".to_string(),
            target_worktree_id: "worktree-2".to_string(),
            requires_hitl: false,
        };

        assert!(!request.requires_hitl);
    }

    /// Test WorktreeStatusResponse construction
    #[test]
    fn test_worktree_status_response_construction() {
        let response = WorktreeStatusResponse {
            agent_id: "agent-1".to_string(),
            repo_id: "repo-1".to_string(),
            worktree_id: "worktree-1".to_string(),
            state: "active".to_string(),
        };

        assert_eq!(response.agent_id, "agent-1");
        assert_eq!(response.repo_id, "repo-1");
        assert_eq!(response.worktree_id, "worktree-1");
        assert_eq!(response.state, "active");
    }

    /// Test WorktreeStatusResponse clone
    #[test]
    fn test_worktree_status_response_clone() {
        let response = WorktreeStatusResponse {
            agent_id: "agent-1".to_string(),
            repo_id: "repo-1".to_string(),
            worktree_id: "worktree-1".to_string(),
            state: "active".to_string(),
        };

        let cloned = response.clone();
        assert_eq!(response.agent_id, cloned.agent_id);
        assert_eq!(response.repo_id, cloned.repo_id);
        assert_eq!(response.worktree_id, cloned.worktree_id);
        assert_eq!(response.state, cloned.state);
    }

    /// Test WorktreeStatusResponse debug
    #[test]
    fn test_worktree_status_response_debug() {
        let response = WorktreeStatusResponse {
            agent_id: "agent-1".to_string(),
            repo_id: "repo-1".to_string(),
            worktree_id: "worktree-1".to_string(),
            state: "active".to_string(),
        };

        let debug_str = format!("{:?}", response);
        assert!(debug_str.contains("WorktreeStatusResponse"));
        assert!(debug_str.contains("agent-1"));
        assert!(debug_str.contains("repo-1"));
    }

    /// Test different worktree states
    #[test]
    fn test_worktree_states() {
        let states = vec!["active", "inactive", "locked", "pending"];

        for state in states {
            let response = WorktreeStatusResponse {
                agent_id: "agent-1".to_string(),
                repo_id: "repo-1".to_string(),
                worktree_id: "worktree-1".to_string(),
                state: state.to_string(),
            };
            assert_eq!(response.state, state);
        }
    }

    /// Test full worktree lifecycle (request structures)
    #[test]
    fn test_worktree_lifecycle_structures() {
        // Bind
        let bind = BindRequest {
            agent_id: "agent-1".to_string(),
            repo_id: "repo-1".to_string(),
            worktree_id: "worktree-1".to_string(),
        };
        assert!(!bind.agent_id.is_empty());

        // Status
        let status = StatusRequest {
            agent_id: "agent-1".to_string(),
        };
        assert!(!status.agent_id.is_empty());

        // Switch
        let switch = SwitchRequest {
            agent_id: "agent-1".to_string(),
            target_worktree_id: "worktree-2".to_string(),
            requires_hitl: false,
        };
        assert!(!switch.target_worktree_id.is_empty());

        // Unbind
        let unbind = UnbindRequest {
            agent_id: "agent-1".to_string(),
        };
        assert!(!unbind.agent_id.is_empty());
    }

    /// Test multiple agents with worktrees
    #[test]
    fn test_multiple_agents_worktrees() {
        let bindings: Vec<BindRequest> = vec!["agent-1", "agent-2", "agent-3"]
            .into_iter()
            .enumerate()
            .map(|(i, agent_id)| BindRequest {
                agent_id: agent_id.to_string(),
                repo_id: "repo-1".to_string(),
                worktree_id: format!("worktree-{}", i + 1),
            })
            .collect();

        assert_eq!(bindings.len(), 3);
        assert_eq!(bindings[0].agent_id, "agent-1");
        assert_eq!(bindings[0].worktree_id, "worktree-1");
        assert_eq!(bindings[2].agent_id, "agent-3");
        assert_eq!(bindings[2].worktree_id, "worktree-3");
    }

    /// Test switch request with HITL required
    #[test]
    fn test_switch_with_hitl_required() {
        let request = SwitchRequest {
            agent_id: "agent-1".to_string(),
            target_worktree_id: "worktree-sensitive".to_string(),
            requires_hitl: true,
        };

        assert!(request.requires_hitl);
        assert_eq!(request.target_worktree_id, "worktree-sensitive");
    }

    /// Test empty strings
    #[test]
    fn test_empty_strings() {
        // Not recommended but should work
        let response = WorktreeStatusResponse {
            agent_id: String::new(),
            repo_id: String::new(),
            worktree_id: String::new(),
            state: String::new(),
        };

        assert!(response.agent_id.is_empty());
        assert!(response.repo_id.is_empty());
        assert!(response.worktree_id.is_empty());
        assert!(response.state.is_empty());
    }

    /// Test worktree response with detailed state
    #[test]
    fn test_worktree_detailed_state() {
        let response = WorktreeStatusResponse {
            agent_id: "agent-1".to_string(),
            repo_id: "repo-main".to_string(),
            worktree_id: "feature-branch-worktree".to_string(),
            state: "active".to_string(),
        };

        assert!(response.worktree_id.contains("feature"));
        assert_eq!(response.state, "active");
    }

    /// Test request chain
    #[test]
    fn test_request_chain() {
        // Simulate a sequence of operations
        let agent_id = "agent-1";
        let repo_id = "repo-1";

        // Initial bind
        let bind1 = BindRequest {
            agent_id: agent_id.to_string(),
            repo_id: repo_id.to_string(),
            worktree_id: "worktree-1".to_string(),
        };
        assert_eq!(bind1.worktree_id, "worktree-1");

        // Switch to new worktree
        let switch = SwitchRequest {
            agent_id: agent_id.to_string(),
            target_worktree_id: "worktree-2".to_string(),
            requires_hitl: false,
        };
        assert_eq!(switch.target_worktree_id, "worktree-2");

        // Check status
        let status = StatusRequest {
            agent_id: agent_id.to_string(),
        };
        assert_eq!(status.agent_id, agent_id);
    }
}
