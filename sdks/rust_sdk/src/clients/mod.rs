pub mod hitl;
pub mod registry;
pub mod router;
pub mod scheduler;
pub mod worktree;

pub mod activity;
pub mod cancellation;
pub mod connector;
pub mod gateway;
pub mod delegation;
pub mod logging;
pub mod negotiation;
pub mod reasoning;
pub mod scheduler_policy;
pub mod tool;

// Phase 3: New protocol clients
pub mod handoff;
pub mod negotiation_room;
pub mod negotiation_room_store;
pub mod workflow;

pub use hitl::HitlClient;
pub use registry::RegistryClient;
pub use router::RouterClient;
pub use scheduler::SchedulerClient;
pub use worktree::WorktreeClient;

pub use activity::ActivityClient;
pub use cancellation::{
    CancelDelegationRequest, CancelDelegationResponse, CancellationFlag, CancellationManager,
    CancellationManagerOptions, CancellationMetadata, CancellationValidationError,
    MIN_GRACE_PERIOD_MS,
};
pub use connector::ConnectorClient;
pub use gateway::{
    GatewayPeerDescriptor, GatewayRedirectEmitter, GatewayRedirectEmitterOptions, PeerSelector,
    PeerSelectorOptions, REGISTRATION_TYPE_STANDARD_AGENT, REGISTRATION_TYPE_SWARM_GATEWAY,
};
pub use delegation::{
    delegate_to_swarm, delegate_to_swarm_with_runtime, DelegateToSwarmOptions,
    DEFAULT_EFFECTIVE_MAX_REDIRECTS, RETRY_AFTER_JITTER_RATIO,
};
pub use logging::LoggingClient;
pub use negotiation::NegotiationClient;
pub use reasoning::ReasoningClient;
pub use scheduler_policy::SchedulerPolicyClient;
pub use tool::ToolClient;

// Phase 3: New protocol client exports
pub use handoff::{
    BudgetEnvelope, HandoffClient, HandoffRequest, HandoffResponse, RejectHandoffOptions,
    SwarmDelegationPolicy, DEFAULT_BACKOFF_MULTIPLIER, DEFAULT_INITIAL_BACKOFF_MS,
    DEFAULT_MAX_BACKOFF_MS, DEFAULT_MAX_REDIRECTS, DEFAULT_MAX_RETRIES_ON_OVERLOADED,
    REJECTION_CODE_OVERLOADED, REJECTION_CODE_REDIRECT, REJECTION_CODE_UNSPECIFIED,
};
pub use negotiation_room::NegotiationRoomClient;
pub use negotiation_room_store::{InMemoryNegotiationRoomStore, NegotiationRoomStore};
pub use workflow::WorkflowClient;
