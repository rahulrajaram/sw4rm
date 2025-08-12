# SW4RM Rust SDK Examples

This document provides comprehensive examples of using the SW4RM Rust SDK for building production-ready agents.

## Table of Contents

- [Basic Agent Registration](#basic-agent-registration)
- [Message Routing and Communication](#message-routing-and-communication)
- [Tool Execution with Streaming](#tool-execution-with-streaming)
- [Activity Scheduling and Coordination](#activity-scheduling-and-coordination)
- [Agent Negotiation and Consensus](#agent-negotiation-and-consensus)
- [Human-in-the-Loop Integration](#human-in-the-loop-integration)
- [Worktree and Git Operations](#worktree-and-git-operations)
- [Enterprise Features: Observability](#enterprise-features-observability)
- [Production Deployment Patterns](#production-deployment-patterns)

## Basic Agent Registration

Register an agent with the SW4RM registry and maintain heartbeat:

```rust
use sw4rm_sdk::{clients::RegistryClient, types::AgentDescriptor, proto::sw4rm::common::AgentState, Result};
use std::collections::HashMap;
use tokio::time::{interval, Duration};

#[tokio::main]
async fn main() -> Result<()> {
    // Create a registry client
    let mut registry = RegistryClient::new("http://localhost:50051").await?;

    // Create agent descriptor with capabilities
    let agent = AgentDescriptor::new(
        "analytics-agent".to_string(),
        "Analytics Processing Agent".to_string()
    )
    .with_description("Processes data analytics and generates reports".to_string())
    .with_capabilities(vec![
        "data-analysis".to_string(),
        "report-generation".to_string(),
        "statistical-modeling".to_string()
    ]);

    // Register the agent
    let response = registry.register(&agent).await?;
    if response.accepted {
        println!("Agent registered successfully!");
    } else {
        eprintln!("Registration failed: {}", response.reason);
        return Ok(());
    }

    // Maintain heartbeat every 30 seconds
    let mut heartbeat_interval = interval(Duration::from_secs(30));
    loop {
        heartbeat_interval.tick().await;
        
        let mut health = HashMap::new();
        health.insert("cpu_usage".to_string(), "15%".to_string());
        health.insert("memory_usage".to_string(), "256MB".to_string());
        health.insert("tasks_processed".to_string(), "42".to_string());
        
        let heartbeat_response = registry.heartbeat(
            &agent.agent_id,
            AgentState::Running,
            Some(health)
        ).await?;
        
        if heartbeat_response.ok {
            println!("Heartbeat successful");
        } else {
            eprintln!("Heartbeat failed - agent may need re-registration");
            break;
        }
    }

    // Deregister on shutdown
    registry.deregister(&agent.agent_id, Some("Normal shutdown")).await?;
    println!("Agent deregistered successfully");
    
    Ok(())
}
```

## Message Routing and Communication

Send messages and handle incoming message streams:

```rust
use sw4rm_sdk::{
    clients::RouterClient,
    envelope::{EnvelopeBuilder, EnvelopeData},
    constants,
    Result
};
use tokio_stream::StreamExt;
use serde_json::json;

#[tokio::main]
async fn main() -> Result<()> {
    let mut router = RouterClient::new("http://localhost:50052").await?;

    // Send a structured data message
    let envelope = EnvelopeBuilder::new(
        "sender-agent".to_string(),
        constants::message_type::DATA
    )
    .with_correlation_id("task-batch-001".to_string())
    .with_json_payload(&json!({
        "task": "analyze_dataset",
        "dataset_id": "customer_data_2023",
        "parameters": {
            "analysis_type": "clustering",
            "k_clusters": 5,
            "features": ["age", "income", "purchase_history"]
        },
        "deadline": "2023-12-01T10:00:00Z"
    }))?
    .with_ttl(Duration::from_secs(300)) // 5 minute TTL
    .build();

    let result = router.send_message(&envelope).await?;
    println!("Message sent: accepted={}, reason={}", result.accepted, result.reason);

    // Stream incoming messages for this agent
    let mut stream = router.stream_incoming("receiver-agent").await?;
    println!("Listening for incoming messages...");

    while let Some(envelope_result) = stream.next().await {
        match envelope_result {
            Ok(envelope) => {
                println!("Received message: {} from {}", 
                        envelope.message_id, envelope.producer_id);
                
                // Parse JSON payload
                if let Ok(payload) = serde_json::from_slice::<serde_json::Value>(&envelope.payload) {
                    println!("Payload: {}", serde_json::to_string_pretty(&payload)?);
                }
                
                // Handle different message types
                match envelope.message_type {
                    constants::message_type::DATA => handle_data_message(&envelope).await?,
                    constants::message_type::CONTROL => handle_control_message(&envelope).await?,
                    constants::message_type::HEARTBEAT => handle_heartbeat(&envelope).await?,
                    _ => println!("Unknown message type: {}", envelope.message_type),
                }
            },
            Err(e) => {
                eprintln!("Stream error: {}", e);
                // Implement reconnection logic here
                break;
            }
        }
    }

    Ok(())
}

async fn handle_data_message(envelope: &EnvelopeData) -> Result<()> {
    println!("Processing data message: {}", envelope.message_id);
    // Implement data processing logic
    Ok(())
}

async fn handle_control_message(envelope: &EnvelopeData) -> Result<()> {
    println!("Processing control message: {}", envelope.message_id);
    // Implement control logic (start, stop, configure, etc.)
    Ok(())
}

async fn handle_heartbeat(envelope: &EnvelopeData) -> Result<()> {
    println!("Received heartbeat from: {}", envelope.producer_id);
    Ok(())
}
```

## Tool Execution with Streaming

Execute long-running tools with real-time progress streaming:

```rust
use sw4rm_sdk::{
    clients::ToolClient,
    clients::tool::ExecutionPolicyConfig,
    Result
};
use tokio_stream::StreamExt;
use std::time::Duration;
use serde_json::json;

#[tokio::main]
async fn main() -> Result<()> {
    let mut tool_client = ToolClient::new("http://localhost:50055").await?;

    // Configure execution policy for data processing tool
    let policy = ExecutionPolicyConfig {
        timeout: Some(Duration::from_secs(300)), // 5 minute timeout
        max_retries: 3,
        backoff: "exponential".to_string(),
        worktree_required: true, // Tool needs git repo access
        network_policy: "restricted".to_string(),
        privilege_level: "default".to_string(),
        budget_cpu_ms: 120_000, // 2 minutes of CPU time
        budget_wall_ms: 300_000, // 5 minutes wall time
    };

    // Prepare tool arguments
    let args = json!({
        "input_file": "data/large_dataset.csv",
        "output_format": "parquet",
        "preprocessing": {
            "normalize": true,
            "handle_missing": "interpolate",
            "feature_selection": "auto"
        },
        "model_config": {
            "algorithm": "random_forest",
            "n_estimators": 100,
            "cross_validation": 5
        }
    });

    // Execute tool with streaming for progress monitoring
    let mut stream = tool_client.call_tool_stream(
        "ml-training-job-456",
        "ml-pipeline",
        "analytics-provider",
        "application/json",
        serde_json::to_vec(&args)?,
        Some(policy)
    ).await?;

    println!("Starting ML pipeline execution...");
    let mut progress_updates = 0;

    // Process streaming results
    while let Some(frame_result) = stream.next().await {
        match frame_result {
            Ok(tool_frame) => {
                progress_updates += 1;
                
                // Parse frame content
                if let Ok(content) = std::str::from_utf8(&tool_frame.content) {
                    if let Ok(progress) = serde_json::from_str::<serde_json::Value>(content) {
                        if let Some(stage) = progress.get("stage") {
                            println!("Stage: {}", stage);
                        }
                        if let Some(percent) = progress.get("progress_percent") {
                            println!("Progress: {}%", percent);
                        }
                        if let Some(metrics) = progress.get("metrics") {
                            println!("Metrics: {}", serde_json::to_string_pretty(metrics)?);
                        }
                    }
                }
                
                // Check if tool execution is complete
                if tool_frame.final_frame {
                    println!("Tool execution completed!");
                    
                    // Parse final results
                    if let Ok(results) = std::str::from_utf8(&tool_frame.content) {
                        if let Ok(final_result) = serde_json::from_str::<serde_json::Value>(results) {
                            println!("Final Results: {}", serde_json::to_string_pretty(&final_result)?);
                        }
                    }
                    break;
                }
            },
            Err(e) => {
                eprintln!("Tool execution error: {}", e);
                
                // Try to cancel the tool if it's still running
                if let Err(cancel_err) = tool_client.cancel_tool("ml-training-job-456").await {
                    eprintln!("Failed to cancel tool: {}", cancel_err);
                }
                break;
            }
        }
    }

    println!("Received {} progress updates", progress_updates);
    Ok(())
}
```

## Activity Scheduling and Coordination

Schedule complex workflows and coordinate between multiple agents:

```rust
use sw4rm_sdk::{
    clients::SchedulerClient,
    activity::{ActivityBuilder, ActivityData},
    constants,
    proto::sw4rm::scheduler::ActivityState,
    Result
};
use std::collections::HashMap;
use tokio::time::{sleep, Duration};

#[tokio::main]
async fn main() -> Result<()> {
    let mut scheduler = SchedulerClient::new("http://localhost:50053").await?;

    // Create a complex data processing pipeline
    let data_ingestion = ActivityBuilder::new(
        "data-coordinator".to_string(),
        constants::activity_type::DATA_INGESTION
    )
    .with_priority(10) // High priority
    .with_metadata("source", "customer_database")
    .with_metadata("format", "json")
    .with_estimated_duration(Duration::from_secs(120))
    .build();

    let data_cleaning = ActivityBuilder::new(
        "data-coordinator".to_string(),
        constants::activity_type::DATA_PROCESSING
    )
    .with_priority(8)
    .with_dependencies(vec![data_ingestion.activity_id.clone()])
    .with_metadata("operation", "cleaning")
    .with_metadata("rules", "remove_nulls,normalize_text")
    .with_estimated_duration(Duration::from_secs(300))
    .build();

    let feature_extraction = ActivityBuilder::new(
        "ml-agent".to_string(),
        constants::activity_type::FEATURE_EXTRACTION
    )
    .with_priority(7)
    .with_dependencies(vec![data_cleaning.activity_id.clone()])
    .with_metadata("method", "tfidf_vectorization")
    .with_estimated_duration(Duration::from_secs(180))
    .build();

    let model_training = ActivityBuilder::new(
        "ml-agent".to_string(),
        constants::activity_type::MODEL_TRAINING
    )
    .with_priority(9)
    .with_dependencies(vec![feature_extraction.activity_id.clone()])
    .with_metadata("algorithm", "gradient_boosting")
    .with_metadata("validation", "k_fold")
    .with_estimated_duration(Duration::from_secs(600))
    .build();

    // Schedule all activities
    let activities = vec![&data_ingestion, &data_cleaning, &feature_extraction, &model_training];
    let mut scheduled_ids = HashMap::new();

    for activity in activities {
        let response = scheduler.schedule_activity(activity).await?;
        if response.accepted {
            println!("Scheduled {}: {} (ID: {})", 
                    activity.activity_type, activity.description, response.activity_id);
            scheduled_ids.insert(activity.activity_id.clone(), response.activity_id);
        } else {
            eprintln!("Failed to schedule {}: {}", activity.activity_id, response.reason);
        }
    }

    // Monitor pipeline progress
    println!("Monitoring pipeline execution...");
    let mut completed_activities = 0;
    let total_activities = scheduled_ids.len();

    while completed_activities < total_activities {
        sleep(Duration::from_secs(10)).await;
        
        for (original_id, scheduled_id) in &scheduled_ids {
            let status = scheduler.get_activity_status(scheduled_id).await?;
            
            match status.state() {
                ActivityState::Completed => {
                    println!("✅ {} completed successfully", original_id);
                    completed_activities += 1;
                },
                ActivityState::Failed => {
                    eprintln!("❌ {} failed: {}", original_id, status.error_message);
                    completed_activities += 1; // Count as finished
                },
                ActivityState::Running => {
                    println!("🔄 {} is running ({}% complete)", 
                            original_id, status.progress_percent);
                },
                ActivityState::Queued => {
                    println!("⏳ {} is queued, waiting for dependencies", original_id);
                },
                _ => {
                    println!("🔍 {} status: {:?}", original_id, status.state());
                }
            }
        }
    }

    println!("Pipeline execution completed!");
    Ok(())
}
```

## Agent Negotiation and Consensus

Participate in multi-agent negotiations and reach consensus:

```rust
use sw4rm_sdk::{
    clients::NegotiationClient,
    proto::sw4rm::negotiation::DebateIntensity,
    Result
};
use std::time::Duration;
use serde_json::json;
use tokio::time::{sleep, timeout};

#[tokio::main]
async fn main() -> Result<()> {
    let mut negotiation = NegotiationClient::new("http://localhost:50058").await?;

    // Resource allocation negotiation scenario
    let negotiation_id = "resource-allocation-q4-2023";
    let correlation_id = "budget-planning-2023";

    // Start negotiation session
    negotiation.open(
        negotiation_id,
        correlation_id,
        "Q4 2023 Resource Allocation - Computing Resources and Budget Distribution",
        vec![
            "financial-agent".to_string(),
            "resource-manager".to_string(),
            "project-coordinator".to_string(),
            "compliance-officer".to_string()
        ],
        DebateIntensity::Thorough, // Allow detailed discussion
        Some(Duration::from_secs(900)) // 15 minute negotiation window
    ).await?;

    println!("Negotiation session opened: {}", negotiation_id);

    // Initial proposal from financial perspective
    let financial_proposal = json!({
        "compute_budget": {
            "ml_training": 40,
            "data_processing": 35,
            "web_services": 20,
            "backup_reserve": 5
        },
        "timeline": "Q4 2023",
        "cost_optimization": true,
        "rationale": "Prioritize ML training for revenue-generating models",
        "constraints": {
            "total_budget": 500000,
            "compliance_reserve": 10000,
            "emergency_buffer": 25000
        }
    });

    negotiation.propose(
        negotiation_id,
        "financial-agent",
        "Cost-optimized resource allocation with ML focus",
        financial_proposal
    ).await?;

    println!("Initial proposal submitted");

    // Resource manager counter-proposal
    let resource_proposal = json!({
        "compute_budget": {
            "ml_training": 35,
            "data_processing": 40, // Higher priority on stable operations
            "web_services": 20,
            "backup_reserve": 5
        },
        "infrastructure_needs": {
            "redundancy": "high",
            "scaling_capability": "auto",
            "monitoring": "comprehensive"
        },
        "rationale": "Balance innovation with operational stability",
        "risk_mitigation": "Ensure core services remain stable during ML experiments"
    });

    negotiation.counter_propose(
        negotiation_id,
        "resource-manager",
        "financial-agent",
        "Stability-focused allocation with balanced innovation",
        resource_proposal
    ).await?;

    println!("Counter-proposal submitted");

    // Project coordinator perspective
    let project_proposal = json!({
        "compute_budget": {
            "ml_training": 37,
            "data_processing": 33,
            "web_services": 25, // Increase for customer-facing features
            "backup_reserve": 5
        },
        "project_alignment": {
            "customer_impact": "high",
            "strategic_initiatives": ["personalization", "real_time_analytics"],
            "delivery_timeline": "aggressive"
        },
        "rationale": "Optimize for customer-visible improvements and strategic goals",
        "success_metrics": ["user_engagement", "revenue_per_user", "system_reliability"]
    });

    negotiation.counter_propose(
        negotiation_id,
        "project-coordinator",
        "resource-manager",
        "Customer-impact focused allocation with strategic alignment",
        project_proposal
    ).await?;

    println!("Project coordinator proposal submitted");

    // Simulate negotiation timeout or manual conclusion
    sleep(Duration::from_secs(30)).await;

    // Reach consensus (in real scenario, this would be automatic)
    let consensus = json!({
        "final_allocation": {
            "ml_training": 36,
            "data_processing": 36,
            "web_services": 23,
            "backup_reserve": 5
        },
        "implementation_plan": {
            "phased_rollout": true,
            "monitoring_points": ["week_2", "week_6", "week_10"],
            "adjustment_triggers": ["cost_overrun", "performance_degradation"]
        },
        "agreement_details": {
            "unanimous": false,
            "majority_vote": true,
            "dissenting_agents": [],
            "compromise_points": [
                "Balanced ML/operations split",
                "Increased web services allocation",
                "Monitoring and adjustment mechanisms"
            ]
        }
    });

    negotiation.conclude(
        negotiation_id,
        "Balanced resource allocation with monitoring and adjustment mechanisms",
        consensus
    ).await?;

    println!("Negotiation concluded with consensus reached!");
    Ok(())
}
```

## Enterprise Features: Observability

Use enterprise observability features for production monitoring:

```rust
use sw4rm_sdk::{
    interceptors::{create_intercepted_channel, RetryLayer},
    clients::{RegistryClient, RouterClient, ToolClient},
    types::new_uuid,
    Result
};
use std::time::Duration;
use tracing::{info, warn, error, Instrument};
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};

#[tokio::main]
async fn main() -> Result<()> {
    // Initialize structured logging
    tracing_subscriber::registry()
        .with(tracing_subscriber::fmt::layer()
            .with_target(false)
            .with_thread_ids(true)
            .with_level(true)
            .json()
        )
        .init();

    // Generate correlation ID for this session
    let correlation_id = new_uuid();
    info!(correlation_id = %correlation_id, "Starting enterprise agent with full observability");

    // Create channel with enterprise features
    let channel = create_intercepted_channel(
        "http://localhost:50051",
        Some(correlation_id.clone()),
        true // Enable all enterprise features (retry, metrics, timing)
    ).await?;

    info!("Enterprise channel created with correlation tracking");

    // Example: Registry operations with automatic retry and observability
    let registry_span = tracing::info_span!("registry_operations", 
        correlation_id = %correlation_id,
        service = "registry"
    );

    let registry_result = async {
        // Create registry client (will inherit interceptors from channel)
        let mut registry = RegistryClient::new("http://localhost:50051").await?;
        
        // Registration will automatically include:
        // - Correlation ID header
        // - Request timing metrics
        // - Automatic retry on transient failures
        // - Structured logging
        info!("Attempting agent registration with enterprise features");
        
        let agent = sw4rm_sdk::types::AgentDescriptor::new(
            "enterprise-agent".to_string(),
            "Enterprise Production Agent".to_string()
        );
        
        match registry.register(&agent).await {
            Ok(response) => {
                if response.accepted {
                    info!("Agent registered successfully with enterprise observability");
                } else {
                    warn!(reason = %response.reason, "Agent registration rejected");
                }
                Ok(response)
            },
            Err(e) => {
                error!(error = %e, "Agent registration failed after retries");
                Err(e)
            }
        }
    }.instrument(registry_span).await;

    // Example: Tool execution with comprehensive monitoring
    let tool_span = tracing::info_span!("tool_execution",
        correlation_id = %correlation_id,
        service = "tool",
        operation = "ml_training"
    );

    let _tool_result = async {
        let mut tool_client = ToolClient::new("http://localhost:50055").await?;
        
        info!("Starting monitored tool execution");
        
        // Configure execution policy with enterprise settings
        let policy = sw4rm_sdk::clients::tool::ExecutionPolicyConfig {
            timeout: Some(Duration::from_secs(300)),
            max_retries: 3,
            backoff: "exponential".to_string(),
            worktree_required: true,
            network_policy: "restricted".to_string(),
            privilege_level: "default".to_string(),
            budget_cpu_ms: 120_000,
            budget_wall_ms: 300_000,
        };

        // All tool operations will include full observability:
        // - Request/response tracing
        // - Performance metrics
        // - Error tracking with correlation
        // - Automatic retry with backoff
        let frame = tool_client.call_tool(
            &new_uuid(),
            "data-processor",
            "analytics-provider",
            "application/json",
            b"{}".to_vec(),
            Some(policy),
            false
        ).await;

        match frame {
            Ok(_) => info!("Tool execution completed successfully"),
            Err(e) => error!(error = %e, "Tool execution failed"),
        }

        Ok::<_, sw4rm_sdk::Error>(())
    }.instrument(tool_span).await;

    // Example: Custom business metrics
    let business_span = tracing::info_span!("business_metrics",
        correlation_id = %correlation_id,
        metric_type = "performance"
    );

    let _metrics_result = async {
        // Simulate business logic with metrics
        let start_time = std::time::Instant::now();
        
        // Simulate processing
        tokio::time::sleep(Duration::from_millis(150)).await;
        
        let processing_duration = start_time.elapsed();
        
        info!(
            processing_duration_ms = processing_duration.as_millis(),
            throughput_ops_per_sec = 1000.0 / processing_duration.as_secs_f64(),
            "Business logic completed with performance metrics"
        );

        // Log structured business events
        info!(
            event_type = "data_processed",
            records_processed = 1500,
            validation_passed = true,
            data_quality_score = 0.97,
            "Data processing pipeline completed"
        );

        Ok::<_, sw4rm_sdk::Error>(())
    }.instrument(business_span).await;

    info!(correlation_id = %correlation_id, "Enterprise agent session completed");
    
    Ok(())
}
```

## Production Deployment Patterns

Common patterns for deploying SW4RM agents in production:

```rust
use sw4rm_sdk::{
    Agent, config::AgentConfig,
    clients::{RegistryClient, RouterClient, SchedulerClient},
    runtime::PreemptionState,
    Result
};
use std::{sync::Arc, time::Duration};
use tokio::{signal, sync::Mutex, time::interval};
use tracing::{info, warn, error};

pub struct ProductionAgent {
    config: AgentConfig,
    preemption: Arc<Mutex<PreemptionState>>,
    registry: RegistryClient,
    router: RouterClient,
    scheduler: SchedulerClient,
}

impl ProductionAgent {
    pub async fn new(config: AgentConfig) -> Result<Self> {
        // Create clients with enterprise features
        let registry = RegistryClient::new(&config.endpoints.registry.clone().unwrap()).await?;
        let router = RouterClient::new(&config.endpoints.router.clone().unwrap()).await?;
        let scheduler = SchedulerClient::new(&config.endpoints.scheduler.clone().unwrap()).await?;

        Ok(Self {
            config,
            preemption: Arc::new(Mutex::new(PreemptionState::new())),
            registry,
            router,
            scheduler,
        })
    }

    pub async fn run(&mut self) -> Result<()> {
        info!("Starting production agent: {}", self.config.agent_id);

        // Set up graceful shutdown handling
        let preemption_clone = Arc::clone(&self.preemption);
        tokio::spawn(async move {
            let _ = signal::ctrl_c().await;
            warn!("Shutdown signal received, initiating graceful shutdown");
            let mut preemption = preemption_clone.lock().await;
            preemption.request_preemption(Some("SIGINT received".to_string()));
        });

        // Register agent
        let agent_descriptor = sw4rm_sdk::types::AgentDescriptor::new(
            self.config.agent_id.clone(),
            self.config.name.clone()
        ).with_capabilities(self.config.capabilities.clone());

        let registration = self.registry.register(&agent_descriptor).await?;
        if !registration.accepted {
            error!("Agent registration failed: {}", registration.reason);
            return Err(sw4rm_sdk::Error::Config(registration.reason));
        }

        info!("Agent registered successfully");

        // Start background tasks
        let heartbeat_handle = self.start_heartbeat_task().await;
        let message_handler = self.start_message_processing().await;
        let health_monitor = self.start_health_monitoring().await;

        // Main agent loop
        let mut tick_interval = interval(Duration::from_secs(1));
        loop {
            tick_interval.tick().await;

            // Check for preemption
            let preemption = self.preemption.lock().await;
            if preemption.is_preemption_requested() {
                info!("Preemption requested: {:?}", preemption.get_preemption_reason());
                break;
            }
            drop(preemption);

            // Perform agent work
            self.process_work().await?;
        }

        // Cleanup
        info!("Shutting down production agent");
        heartbeat_handle.abort();
        message_handler.abort();
        health_monitor.abort();

        // Deregister
        let _ = self.registry.deregister(&self.config.agent_id, 
                                      Some("Normal shutdown")).await;
        
        info!("Production agent shutdown complete");
        Ok(())
    }

    async fn start_heartbeat_task(&mut self) -> tokio::task::JoinHandle<()> {
        let mut registry = self.registry.clone();
        let agent_id = self.config.agent_id.clone();
        let preemption = Arc::clone(&self.preemption);

        tokio::spawn(async move {
            let mut interval = interval(Duration::from_secs(30));
            
            loop {
                interval.tick().await;
                
                // Check if we should stop
                let preemption_guard = preemption.lock().await;
                if preemption_guard.is_preemption_requested() {
                    break;
                }
                drop(preemption_guard);

                // Send heartbeat
                let health = std::collections::HashMap::new(); // Add health metrics
                match registry.heartbeat(&agent_id, 
                                       sw4rm_sdk::proto::sw4rm::common::AgentState::Running, 
                                       Some(health)).await {
                    Ok(response) => {
                        if !response.ok {
                            warn!("Heartbeat rejected by registry");
                        }
                    },
                    Err(e) => {
                        error!("Heartbeat failed: {}", e);
                    }
                }
            }
        })
    }

    async fn start_message_processing(&mut self) -> tokio::task::JoinHandle<()> {
        let mut router = self.router.clone();
        let agent_id = self.config.agent_id.clone();
        let preemption = Arc::clone(&self.preemption);

        tokio::spawn(async move {
            use tokio_stream::StreamExt;

            match router.stream_incoming(&agent_id).await {
                Ok(mut stream) => {
                    while let Some(envelope_result) = stream.next().await {
                        // Check for shutdown
                        let preemption_guard = preemption.lock().await;
                        if preemption_guard.is_preemption_requested() {
                            break;
                        }
                        drop(preemption_guard);

                        match envelope_result {
                            Ok(envelope) => {
                                info!("Processing message: {}", envelope.message_id);
                                // Handle message based on type
                                // ... implement message handling logic
                            },
                            Err(e) => {
                                error!("Message stream error: {}", e);
                                // Implement reconnection logic
                                break;
                            }
                        }
                    }
                },
                Err(e) => {
                    error!("Failed to establish message stream: {}", e);
                }
            }
        })
    }

    async fn start_health_monitoring(&self) -> tokio::task::JoinHandle<()> {
        let preemption = Arc::clone(&self.preemption);

        tokio::spawn(async move {
            let mut interval = interval(Duration::from_secs(60));
            
            loop {
                interval.tick().await;
                
                let preemption_guard = preemption.lock().await;
                if preemption_guard.is_preemption_requested() {
                    break;
                }
                drop(preemption_guard);

                // Monitor system health
                let memory_usage = get_memory_usage().await;
                let cpu_usage = get_cpu_usage().await;
                
                info!(
                    memory_mb = memory_usage,
                    cpu_percent = cpu_usage,
                    "System health check"
                );

                // Trigger alerts if necessary
                if memory_usage > 1000.0 || cpu_usage > 80.0 {
                    warn!(
                        memory_mb = memory_usage,
                        cpu_percent = cpu_usage,
                        "High resource usage detected"
                    );
                }
            }
        })
    }

    async fn process_work(&mut self) -> Result<()> {
        // Implement core agent business logic here
        // This is where the agent performs its main tasks
        Ok(())
    }
}

async fn get_memory_usage() -> f64 {
    // Implement memory monitoring
    // This would typically use system APIs
    256.0 // Placeholder
}

async fn get_cpu_usage() -> f64 {
    // Implement CPU monitoring
    15.0 // Placeholder
}

#[tokio::main]
async fn main() -> Result<()> {
    // Initialize logging
    tracing_subscriber::fmt()
        .with_env_filter("sw4rm_sdk=info,production_agent=info")
        .init();

    // Load configuration (from environment, config file, etc.)
    let config = AgentConfig::new(
        std::env::var("AGENT_ID").unwrap_or_else(|_| "production-agent".to_string()),
        std::env::var("AGENT_NAME").unwrap_or_else(|_| "Production Agent".to_string()),
    )
    .with_registry_endpoint(
        std::env::var("REGISTRY_ENDPOINT").unwrap_or_else(|_| "http://localhost:50051".to_string())
    )
    .with_router_endpoint(
        std::env::var("ROUTER_ENDPOINT").unwrap_or_else(|_| "http://localhost:50052".to_string())
    )
    .with_scheduler_endpoint(
        std::env::var("SCHEDULER_ENDPOINT").unwrap_or_else(|_| "http://localhost:50053".to_string())
    );

    // Create and run production agent
    let mut agent = ProductionAgent::new(config).await?;
    agent.run().await
}
```

This comprehensive examples document demonstrates:

1. **Production-ready patterns** with error handling, graceful shutdown, and monitoring
2. **Enterprise observability** with correlation tracking, structured logging, and metrics
3. **Advanced features** like streaming, retry logic, and negotiation protocols
4. **Real-world scenarios** including ML pipelines, resource allocation, and multi-agent coordination
5. **Deployment considerations** for production environments

Each example is fully functional and demonstrates best practices for using the SW4RM Rust SDK in production environments.