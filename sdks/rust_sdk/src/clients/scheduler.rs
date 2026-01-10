use crate::proto::sw4rm::scheduler::scheduler_service_client::SchedulerServiceClient;
use crate::proto::sw4rm::scheduler::{
    ActivityEntry, PollActivityBufferRequest, PreemptRequest, PurgeActivityRequest,
    ShutdownAgentRequest, SubmitTaskRequest,
};
use crate::{Error, Result};
use prost_types;
use tonic::transport::{Channel, Endpoint};

/// Client for interacting with the SW4RM Scheduler service
#[derive(Debug, Clone)]
pub struct SchedulerClient {
    client: SchedulerServiceClient<Channel>,
}

impl SchedulerClient {
    /// Create a new scheduler client
    pub async fn new(endpoint: &str) -> Result<Self> {
        let channel = Endpoint::from_shared(endpoint.to_string())
            .map_err(|e| Error::Config(format!("Invalid endpoint: {}", e)))?
            .connect()
            .await?;

        Ok(Self {
            client: SchedulerServiceClient::new(channel),
        })
    }

    /// Submit a task to the scheduler
    pub async fn submit_task(
        &mut self,
        task_id: &str,
        agent_id: &str,
        priority: i32,
        params: Vec<u8>,
        content_type: &str,
        scope: &str,
    ) -> Result<()> {
        let request = tonic::Request::new(SubmitTaskRequest {
            task_id: task_id.to_string(),
            agent_id: agent_id.to_string(),
            priority,
            params,
            content_type: content_type.to_string(),
            scope: scope.to_string(),
        });

        self.client.submit_task(request).await?;
        Ok(())
    }

    /// Request preemption for an agent
    pub async fn request_preemption(
        &mut self,
        agent_id: &str,
        task_id: &str,
        reason: &str,
    ) -> Result<()> {
        let request = tonic::Request::new(PreemptRequest {
            agent_id: agent_id.to_string(),
            task_id: task_id.to_string(),
            reason: reason.to_string(),
        });

        self.client.request_preemption(request).await?;
        Ok(())
    }

    /// Request agent shutdown
    pub async fn shutdown_agent(
        &mut self,
        agent_id: &str,
        grace_period: Option<std::time::Duration>,
    ) -> Result<()> {
        let grace_period = grace_period.map(|d| prost_types::Duration {
            seconds: d.as_secs() as i64,
            nanos: d.subsec_nanos() as i32,
        });

        let request = tonic::Request::new(ShutdownAgentRequest {
            agent_id: agent_id.to_string(),
            grace_period,
        });

        self.client.shutdown_agent(request).await?;
        Ok(())
    }

    /// Purge activities for specific task IDs
    pub async fn purge_activities(&mut self, agent_id: &str, task_ids: Vec<String>) -> Result<u32> {
        let request = tonic::Request::new(PurgeActivityRequest {
            agent_id: agent_id.to_string(),
            task_ids,
        });

        let response = self.client.purge_activity(request).await?;
        Ok(response.into_inner().purged)
    }

    /// Get activity buffer for an agent
    pub async fn get_activity_buffer(&mut self, agent_id: &str) -> Result<Vec<ActivityEntry>> {
        let request = tonic::Request::new(PollActivityBufferRequest {
            agent_id: agent_id.to_string(),
        });

        let response = self.client.poll_activity_buffer(request).await?;
        Ok(response.into_inner().entries)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Test SubmitTaskRequest construction
    #[test]
    fn test_submit_task_request_construction() {
        let request = SubmitTaskRequest {
            task_id: "task-123".to_string(),
            agent_id: "agent-1".to_string(),
            priority: 5,
            params: b"test params".to_vec(),
            content_type: "application/json".to_string(),
            scope: "test-scope".to_string(),
        };

        assert_eq!(request.task_id, "task-123");
        assert_eq!(request.agent_id, "agent-1");
        assert_eq!(request.priority, 5);
        assert_eq!(request.params, b"test params".to_vec());
        assert_eq!(request.content_type, "application/json");
        assert_eq!(request.scope, "test-scope");
    }

    /// Test SubmitTaskRequest with default values
    #[test]
    fn test_submit_task_request_defaults() {
        let request = SubmitTaskRequest {
            task_id: "task-1".to_string(),
            agent_id: "agent-1".to_string(),
            priority: 0,
            params: vec![],
            content_type: String::new(),
            scope: String::new(),
        };

        assert_eq!(request.priority, 0);
        assert!(request.params.is_empty());
        assert!(request.content_type.is_empty());
        assert!(request.scope.is_empty());
    }

    /// Test PreemptRequest construction
    #[test]
    fn test_preempt_request_construction() {
        let request = PreemptRequest {
            agent_id: "agent-1".to_string(),
            task_id: "task-1".to_string(),
            reason: "Higher priority task".to_string(),
        };

        assert_eq!(request.agent_id, "agent-1");
        assert_eq!(request.task_id, "task-1");
        assert_eq!(request.reason, "Higher priority task");
    }

    /// Test PreemptRequest with empty reason
    #[test]
    fn test_preempt_request_empty_reason() {
        let request = PreemptRequest {
            agent_id: "agent-1".to_string(),
            task_id: "task-1".to_string(),
            reason: String::new(),
        };

        assert!(request.reason.is_empty());
    }

    /// Test ShutdownAgentRequest without grace period
    #[test]
    fn test_shutdown_agent_request_no_grace_period() {
        let request = ShutdownAgentRequest {
            agent_id: "agent-1".to_string(),
            grace_period: None,
        };

        assert_eq!(request.agent_id, "agent-1");
        assert!(request.grace_period.is_none());
    }

    /// Test ShutdownAgentRequest with grace period
    #[test]
    fn test_shutdown_agent_request_with_grace_period() {
        let grace_period = prost_types::Duration {
            seconds: 30,
            nanos: 0,
        };

        let request = ShutdownAgentRequest {
            agent_id: "agent-1".to_string(),
            grace_period: Some(grace_period.clone()),
        };

        assert_eq!(request.agent_id, "agent-1");
        assert!(request.grace_period.is_some());
        assert_eq!(request.grace_period.unwrap().seconds, 30);
    }

    /// Test ShutdownAgentRequest with fractional grace period
    #[test]
    fn test_shutdown_agent_request_fractional_grace_period() {
        let grace_period = prost_types::Duration {
            seconds: 30,
            nanos: 500_000_000, // 0.5 seconds
        };

        let request = ShutdownAgentRequest {
            agent_id: "agent-1".to_string(),
            grace_period: Some(grace_period.clone()),
        };

        let gp = request.grace_period.unwrap();
        assert_eq!(gp.seconds, 30);
        assert_eq!(gp.nanos, 500_000_000);
    }

    /// Test PollActivityBufferRequest construction
    #[test]
    fn test_poll_activity_buffer_request() {
        let request = PollActivityBufferRequest {
            agent_id: "agent-1".to_string(),
        };

        assert_eq!(request.agent_id, "agent-1");
    }

    /// Test PurgeActivityRequest with multiple task IDs
    #[test]
    fn test_purge_activity_request_multiple_tasks() {
        let request = PurgeActivityRequest {
            agent_id: "agent-1".to_string(),
            task_ids: vec![
                "task-1".to_string(),
                "task-2".to_string(),
                "task-3".to_string(),
            ],
        };

        assert_eq!(request.agent_id, "agent-1");
        assert_eq!(request.task_ids.len(), 3);
        assert!(request.task_ids.contains(&"task-1".to_string()));
        assert!(request.task_ids.contains(&"task-2".to_string()));
        assert!(request.task_ids.contains(&"task-3".to_string()));
    }

    /// Test PurgeActivityRequest with empty task IDs
    #[test]
    fn test_purge_activity_request_empty_tasks() {
        let request = PurgeActivityRequest {
            agent_id: "agent-1".to_string(),
            task_ids: vec![],
        };

        assert!(request.task_ids.is_empty());
    }

    /// Test priority bounds
    #[test]
    fn test_priority_bounds() {
        // Test lower bound
        let request_low = SubmitTaskRequest {
            task_id: "task-1".to_string(),
            agent_id: "agent-1".to_string(),
            priority: -19,
            params: vec![],
            content_type: String::new(),
            scope: String::new(),
        };
        assert_eq!(request_low.priority, -19);

        // Test upper bound
        let request_high = SubmitTaskRequest {
            task_id: "task-1".to_string(),
            agent_id: "agent-1".to_string(),
            priority: 20,
            params: vec![],
            content_type: String::new(),
            scope: String::new(),
        };
        assert_eq!(request_high.priority, 20);
    }

    /// Test multiple operations in sequence (request structures)
    #[test]
    fn test_multiple_request_structures() {
        // Submit
        let submit = SubmitTaskRequest {
            task_id: "task-1".to_string(),
            agent_id: "agent-1".to_string(),
            priority: 5,
            params: b"params".to_vec(),
            content_type: "application/json".to_string(),
            scope: "scope".to_string(),
        };
        assert!(!submit.task_id.is_empty());

        // Poll
        let poll = PollActivityBufferRequest {
            agent_id: "agent-1".to_string(),
        };
        assert!(!poll.agent_id.is_empty());

        // Preempt
        let preempt = PreemptRequest {
            agent_id: "agent-1".to_string(),
            task_id: "task-1".to_string(),
            reason: "reason".to_string(),
        };
        assert!(!preempt.reason.is_empty());

        // Purge
        let purge = PurgeActivityRequest {
            agent_id: "agent-1".to_string(),
            task_ids: vec!["task-1".to_string()],
        };
        assert_eq!(purge.task_ids.len(), 1);
    }
}
