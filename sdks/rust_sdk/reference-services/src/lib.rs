pub mod proto {
    pub mod sw4rm {
        pub mod common {
            tonic::include_proto!("sw4rm.common");
        }
        pub mod registry {
            tonic::include_proto!("sw4rm.registry");
        }
        pub mod router {
            tonic::include_proto!("sw4rm.router");
        }
        pub mod scheduler {
            tonic::include_proto!("sw4rm.scheduler");
        }
        pub mod handoff {
            tonic::include_proto!("sw4rm.handoff");
        }
        pub mod workflow {
            tonic::include_proto!("sw4rm.workflow");
        }
        pub mod negotiation_room {
            tonic::include_proto!("sw4rm.negotiation_room");
        }
    }
}

pub mod registry;
pub mod router;
pub mod scheduler;
pub mod agents;
pub mod coordination;
