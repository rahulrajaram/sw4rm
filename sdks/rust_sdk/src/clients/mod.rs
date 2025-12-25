pub mod hitl;
pub mod registry;
pub mod router;
pub mod scheduler;
pub mod worktree;

pub mod activity;
pub mod connector;
pub mod logging;
pub mod negotiation;
pub mod reasoning;
pub mod scheduler_policy;
pub mod tool;

// Phase 3: New protocol clients
pub mod handoff;
pub mod negotiation_room;
pub mod workflow;

pub use hitl::HitlClient;
pub use registry::RegistryClient;
pub use router::RouterClient;
pub use scheduler::SchedulerClient;
pub use worktree::WorktreeClient;

pub use activity::ActivityClient;
pub use connector::ConnectorClient;
pub use logging::LoggingClient;
pub use negotiation::NegotiationClient;
pub use reasoning::ReasoningClient;
pub use scheduler_policy::SchedulerPolicyClient;
pub use tool::ToolClient;

// Phase 3: New protocol client exports
pub use handoff::HandoffClient;
pub use negotiation_room::NegotiationRoomClient;
pub use workflow::WorkflowClient;
