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
    }
}

pub mod registry;
pub mod router;