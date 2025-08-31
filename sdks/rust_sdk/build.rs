use std::env;
use std::path::PathBuf;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let out_dir = env::var("OUT_DIR").unwrap();

    // Determine the proto directory robustly
    // Priority:
    // 1) PROTO_DIR env var (absolute or relative)
    // 2) workspace root `protos/` (two levels up from this crate)
    // 3) project root `protos/` computed from CARGO_MANIFEST_DIR
    let manifest_dir = PathBuf::from(env::var("CARGO_MANIFEST_DIR").unwrap());
    let proto_dir: PathBuf = if let Ok(dir) = env::var("PROTO_DIR") {
        PathBuf::from(dir)
    } else {
        // sdks/rust_sdk -> workspace root
        let candidate = manifest_dir.join("..").join("..").join("protos");
        if candidate.exists() {
            candidate
        } else {
            manifest_dir.join("../../protos")
        }
    };

    // Check if proto files exist
    let wanted = [
        "common.proto",
        "registry.proto",
        "router.proto",
        "scheduler.proto",
        "hitl.proto",
        "worktree.proto",
        "tool.proto",
        "connector.proto",
        "negotiation.proto",
        "reasoning.proto",
        "logging.proto",
        // Additive policy/negotiation artifacts and activity APIs
        "policy.proto",
        "scheduler_policy.proto",
        "activity.proto",
    ];
    let mut existing_files = Vec::new();
    for file in &wanted {
        let path = proto_dir.join(file);
        if path.exists() {
            println!("cargo:rerun-if-changed={}", path.display());
            existing_files.push(path);
        }
    }

    // If we have proto files, always build them (even if SKIP_PROTO_BUILD is set),
    // since they’re authoritative and improve symmetry with the spec.
    if !existing_files.is_empty() {
        let config = tonic_build::configure()
            .build_server(true)
            .build_client(true)
            .out_dir(&out_dir)
            .include_file("mod.rs");

        config.compile_protos(&existing_files, &[proto_dir.clone()])?;
        println!("cargo:rustc-env=PROTO_GENERATED=true");
        println!("cargo:rustc-cfg=feature=\"proto\"");
        return Ok(());
    }

    // Fallback: generate minimal stubs when protos are absent
    println!("cargo:warning=No proto files found, generating minimal stubs");
    generate_minimal_stubs(&out_dir)?;
    Ok(())
}

fn generate_minimal_stubs(out_dir: &str) -> Result<(), Box<dyn std::error::Error>> {
    let mod_content = r#"
// Minimal stubs when proto files are not available

pub mod sw4rm {
    pub mod common {
        #[derive(Clone, Debug, PartialEq)]
        pub struct Envelope {
            pub message_id: String,
            pub producer_id: String,
            pub message_type: i32,
            pub payload: Vec<u8>,
        }
        
        #[repr(i32)]
        #[derive(Clone, Copy, Debug, PartialEq, Eq)]
        pub enum MessageType {
            Unspecified = 0,
            Control = 1,
            Data = 2,
            Acknowledgement = 5,
        }
    }
    
    pub mod registry {
        #[derive(Clone, Debug)]
        pub struct RegisterAgentRequest;
        
        #[derive(Clone, Debug)]
        pub struct RegisterAgentResponse;
        
        pub mod registry_service_client {
            use tonic::client::GrpcService;
            use tonic::codegen::*;
            
            #[derive(Debug, Clone)]
            pub struct RegistryServiceClient<T> {
                inner: tonic::client::Grpc<T>,
            }
            
            impl<T> RegistryServiceClient<T>
            where
                T: GrpcService<tonic::body::BoxBody>,
                T::Error: Into<StdError>,
                T::ResponseBody: Body<Data = Bytes> + Send + 'static,
                <T::ResponseBody as Body>::Error: Into<StdError> + Send,
            {
                pub fn new(inner: T) -> Self {
                    Self {
                        inner: tonic::client::Grpc::new(inner),
                    }
                }
                
                pub async fn register_agent(
                    &mut self,
                    _request: impl tonic::IntoRequest<super::RegisterAgentRequest>,
                ) -> Result<tonic::Response<super::RegisterAgentResponse>, tonic::Status> {
                    Err(tonic::Status::unimplemented("Stub implementation"))
                }
            }
        }
    }
}
"#;

    std::fs::write(format!("{}/mod.rs", out_dir), mod_content)?;
    Ok(())
}
