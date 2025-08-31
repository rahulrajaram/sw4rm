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
