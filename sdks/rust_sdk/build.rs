use std::path::{Path, PathBuf};
use std::env;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Check if proto building should be skipped (for environments without protoc)
    if env::var("SKIP_PROTO_BUILD").is_ok() {
        let out_dir = env::var("OUT_DIR").unwrap();
        println!("cargo:warning=SKIP_PROTO_BUILD set, generating minimal stubs");
        generate_minimal_stubs(&out_dir)?;
        return Ok(());
    }

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
            // fallback: try workspace/sdks/rust_sdk/../../protos
            manifest_dir.join("../../protos")
        }
    };
    
    // Check if proto files exist
    let proto_files = [
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
    ];

    let mut existing_files = Vec::new();
    for file in &proto_files {
        let path = proto_dir.join(file);
        if path.exists() {
            existing_files.push(path);
            // Re-run if either proto file or included google protos change
            println!("cargo:rerun-if-changed={}", proto_dir.join(file).display());
        } else {
            println!("cargo:warning=Proto file not found: {}", path.display());
        }
    }

    if existing_files.is_empty() {
        println!("cargo:warning=No proto files found, generating minimal stubs");
        generate_minimal_stubs(&out_dir)?;
        return Ok(());
    }

    // Configure tonic-build with proper settings
    let config = tonic_build::configure()
        .build_server(true)
        .build_client(true)
        .out_dir(&out_dir)
        .include_file("mod.rs"); // Generate a mod.rs file

    // No additional type attributes needed - prost handles derives

    // Generate protobuf files
    config.compile_protos(&existing_files, &[proto_dir.clone()])?;

    println!("cargo:rustc-env=PROTO_GENERATED=true");
    println!("cargo:rustc-cfg=feature=\"proto\"");

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
