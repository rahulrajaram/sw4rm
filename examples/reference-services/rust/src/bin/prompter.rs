use anyhow::Result;
use std::fs;
use std::path::PathBuf;
use clap::Parser;
use tracing::info;

use sw4rm_sdk::clients::router::RouterClient;
use sw4rm_sdk::constants;
use sw4rm_sdk::envelope::EnvelopeBuilder;

#[derive(Parser)]
struct Args {
    #[arg(long)]
    file: PathBuf,
}

#[tokio::main]
async fn main() -> Result<()> {
    tracing_subscriber::fmt::init();
    let args = Args::parse();
    if !args.file.exists() { eprintln!("file not found: {}", args.file.display()); std::process::exit(2); }

    let router_host = std::env::var("ROUTER_HOST").unwrap_or_else(|_| "localhost".into());
    let router_port = std::env::var("ROUTER_PORT").unwrap_or_else(|_| "50051".into());
    let router_ep = format!("http://{}:{}", router_host, router_port);
    let mut router = RouterClient::new(&router_ep).await?;

    let raw = fs::read_to_string(&args.file)?;
    let obj: serde_json::Value = serde_json::from_str(&raw).unwrap_or(serde_json::Value::Null);
    let payload = if obj.is_object() && obj.get("stage").and_then(|v| v.as_str()) == Some("run") && obj.get("to").and_then(|v| v.as_str()).unwrap_or("scheduler") == "scheduler" {
        raw.into_bytes()
    } else {
        serde_json::to_vec(&serde_json::json!({
            "schema_version": 1,
            "to": "scheduler",
            "stage": "prompt",
            "params": {"prompt": raw},
        }))?
    };
    let env = EnvelopeBuilder::new("prompter".to_string(), constants::message_type::CONTROL)
        .with_payload(payload)
        .with_content_type("application/vnd.sw4rm.scheduler.command+json;v=1".to_string())
        .build();
    let res = router.send_message(&env).await?;
    println!("accepted= {} reason= {}", res.accepted, res.reason);
    Ok(())
}

