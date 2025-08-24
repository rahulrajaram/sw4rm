use std::path::PathBuf;
use std::env;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let out_dir = env::var("OUT_DIR").unwrap();

    // Use the protos from the parent directory
    let proto_dir = PathBuf::from("../../../protos");
    
    let proto_files = vec![
        proto_dir.join("common.proto"),
        proto_dir.join("registry.proto"),
        proto_dir.join("router.proto"),
        proto_dir.join("scheduler.proto"),
    ];

    // Check if proto files exist
    for file in &proto_files {
        if !file.exists() {
            panic!("Proto file not found: {}", file.display());
        }
        println!("cargo:rerun-if-changed={}", file.display());
    }

    let config = tonic_build::configure()
        .build_server(true)
        .build_client(true)
        .out_dir(&out_dir)
        .include_file("mod.rs");

    config.compile_protos(&proto_files, &[proto_dir.clone()])?;
    
    Ok(())
}