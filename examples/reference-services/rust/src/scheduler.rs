use crate::proto::sw4rm::scheduler::{
    scheduler_service_server::{SchedulerService, SchedulerServiceServer},
    SubmitTaskRequest, SubmitTaskResponse,
    PreemptRequest, PreemptResponse,
    ShutdownAgentRequest, ShutdownAgentResponse,
    PollActivityBufferRequest, PollActivityBufferResponse,
    PurgeActivityRequest, PurgeActivityResponse,
    ActivityEntry,
};
use dashmap::DashMap;
use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};
use tonic::{Request, Response, Status};
use tracing::{info, debug};
use uuid::Uuid;

#[derive(Debug, Clone)]
pub struct TaskInfo {
    pub task_id: String,
    pub agent_id: String,
    pub priority: i32,
    pub params: Vec<u8>,
    pub content_type: String,
    pub scope: String,
    pub submitted_at: u64,
}

#[derive(Debug)]
pub struct SchedulerServiceImpl {
    tasks: Arc<DashMap<String, TaskInfo>>,
    activity_buffer: Arc<DashMap<String, Vec<ActivityEntry>>>,
}

impl SchedulerServiceImpl {
    pub fn new() -> Self {
        info!("Scheduler service initialized");
        Self {
            tasks: Arc::new(DashMap::new()),
            activity_buffer: Arc::new(DashMap::new()),
        }
    }
}

#[tonic::async_trait]
impl SchedulerService for SchedulerServiceImpl {
    async fn submit_task(
        &self,
        request: Request<SubmitTaskRequest>,
    ) -> Result<Response<SubmitTaskResponse>, Status> {
        let req = request.into_inner();
        let task_id = if req.task_id.is_empty() {
            Uuid::new_v4().to_string()
        } else {
            req.task_id
        };

        let current_time = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_secs();

        let task_info = TaskInfo {
            task_id: task_id.clone(),
            agent_id: req.agent_id.clone(),
            priority: req.priority,
            params: req.params,
            content_type: req.content_type,
            scope: req.scope,
            submitted_at: current_time,
        };

        self.tasks.insert(task_id.clone(), task_info);
        info!("Submitted task {} for agent {}", task_id, req.agent_id);

        Ok(Response::new(SubmitTaskResponse {
            accepted: true,
            reason: format!("Task {} submitted successfully", task_id),
        }))
    }

    async fn request_preemption(
        &self,
        request: Request<PreemptRequest>,
    ) -> Result<Response<PreemptResponse>, Status> {
        let req = request.into_inner();
        info!("Preemption requested for task {} (agent {}): {}", req.task_id, req.agent_id, req.reason);
        
        // For this simple implementation, we'll just acknowledge the preemption
        Ok(Response::new(PreemptResponse { enqueued: true }))
    }

    async fn shutdown_agent(
        &self,
        request: Request<ShutdownAgentRequest>,
    ) -> Result<Response<ShutdownAgentResponse>, Status> {
        let req = request.into_inner();
        info!("Shutdown requested for agent {}", req.agent_id);
        
        // Remove all tasks for this agent
        let mut tasks_to_remove = Vec::new();
        for entry in self.tasks.iter() {
            if entry.value().agent_id == req.agent_id {
                tasks_to_remove.push(entry.key().clone());
            }
        }
        
        for task_id in tasks_to_remove {
            self.tasks.remove(&task_id);
        }
        
        // Clear activity buffer for this agent
        self.activity_buffer.remove(&req.agent_id);
        
        Ok(Response::new(ShutdownAgentResponse { ok: true }))
    }

    async fn poll_activity_buffer(
        &self,
        request: Request<PollActivityBufferRequest>,
    ) -> Result<Response<PollActivityBufferResponse>, Status> {
        let req = request.into_inner();
        debug!("Polling activity buffer for agent {}", req.agent_id);
        
        let entries = self.activity_buffer
            .get(&req.agent_id)
            .map(|e| e.clone())
            .unwrap_or_default();
        
        Ok(Response::new(PollActivityBufferResponse { entries }))
    }

    async fn purge_activity(
        &self,
        request: Request<PurgeActivityRequest>,
    ) -> Result<Response<PurgeActivityResponse>, Status> {
        let req = request.into_inner();
        debug!("Purging activity for agent {}, tasks: {:?}", req.agent_id, req.task_ids);
        
        let purged_count = if let Some(mut entries) = self.activity_buffer.get_mut(&req.agent_id) {
            let initial_len = entries.len();
            if req.task_ids.is_empty() {
                entries.clear();
                initial_len
            } else {
                entries.retain(|entry| !req.task_ids.contains(&entry.task_id));
                initial_len - entries.len()
            }
        } else {
            0
        };
        
        Ok(Response::new(PurgeActivityResponse { 
            purged: purged_count as u32 
        }))
    }
}

pub fn create_service() -> SchedulerServiceServer<SchedulerServiceImpl> {
    SchedulerServiceServer::new(SchedulerServiceImpl::new())
}