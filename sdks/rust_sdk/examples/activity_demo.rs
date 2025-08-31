use serde_json::json;
use std::path::Path;
use sw4rm_sdk::activity_buffer::PersistentActivityBuffer;
use sw4rm_sdk::persistence::JsonFilePersistence;
use sw4rm_sdk::prelude::*;

#[tokio::main]
async fn main() -> Result<()> {
    // Initialize logging
    tracing_subscriber::fmt()
        .with_target(false)
        .with_level(true)
        .init();

    tracing::info!("🎯 SW4RM Activity Buffer Demo");
    tracing::info!("📦 SDK Version: {}", sw4rm_sdk::VERSION);

    // Create persistence backend
    let persistence_file = "demo_activity.json";
    let persistence = Box::new(JsonFilePersistence::new(persistence_file));
    let buffer = PersistentActivityBuffer::new(100, Some(persistence))?;

    tracing::info!("📊 Created activity buffer with JSON persistence");

    // Create some test messages
    let agent_id = "activity-demo-agent";

    // Create incoming messages
    for i in 1..=5 {
        let envelope = json!({
            "message_id": format!("incoming-{}", i),
            "producer_id": format!("sender-{}", i),
            "message_type": constants::message_type::DATA,
            "content_type": "application/json",
            "payload": json!({
                "data": format!("Incoming message #{}", i),
                "timestamp": chrono::Utc::now().to_rfc3339()
            }).to_string().as_bytes(),
            "sequence_number": i,
            "correlation_id": new_uuid()
        });

        let record = buffer.record_incoming(envelope)?;
        tracing::info!("📥 Recorded incoming message: {}", record.message_id);
    }

    // Create outgoing messages
    for i in 1..=3 {
        let envelope = json!({
            "message_id": format!("outgoing-{}", i),
            "producer_id": agent_id,
            "message_type": constants::message_type::DATA,
            "content_type": "application/json",
            "payload": json!({
                "response": format!("Response to message #{}", i),
                "timestamp": chrono::Utc::now().to_rfc3339()
            }).to_string().as_bytes(),
            "sequence_number": i,
            "correlation_id": new_uuid()
        });

        let record = buffer.record_outgoing(envelope)?;
        tracing::info!("📤 Recorded outgoing message: {}", record.message_id);
    }

    // Show unacked messages
    let unacked = buffer.unacked()?;
    tracing::info!("🔍 Found {} unacked messages", unacked.len());
    for record in &unacked {
        tracing::info!(
            "  📋 {} ({}) - stage: {}",
            record.message_id,
            record.direction,
            record.ack_stage
        );
    }

    // Process some ACKs
    tracing::info!("✅ Processing ACKs...");

    for i in 1..=3 {
        let ack_data = json!({
            "ack_for_message_id": format!("incoming-{}", i),
            "ack_stage": constants::ack_stage::RECEIVED,
            "error_code": constants::error_code::ERROR_CODE_UNSPECIFIED,
            "note": format!("Message {} received", i)
        });

        if let Some(record) = buffer.ack(&ack_data)? {
            tracing::info!(
                "✅ ACKed message: {} (stage: {})",
                record.message_id,
                record.ack_stage
            );
        }
    }

    // Mark some messages as fulfilled
    for i in 1..=2 {
        let ack_data = json!({
            "ack_for_message_id": format!("incoming-{}", i),
            "ack_stage": constants::ack_stage::FULFILLED,
            "error_code": constants::error_code::ERROR_CODE_UNSPECIFIED,
            "note": format!("Message {} processed successfully", i)
        });

        if let Some(record) = buffer.ack(&ack_data)? {
            tracing::info!(
                "🎉 Fulfilled message: {} (stage: {})",
                record.message_id,
                record.ack_stage
            );
        }
    }

    // Reject one message
    let reject_ack = json!({
        "ack_for_message_id": "incoming-4",
        "ack_stage": constants::ack_stage::REJECTED,
        "error_code": constants::error_code::VALIDATION_ERROR,
        "note": "Invalid message format"
    });

    if let Some(record) = buffer.ack(&reject_ack)? {
        tracing::warn!(
            "❌ Rejected message: {} (reason: {})",
            record.message_id,
            record.ack_note
        );
    }

    // Show updated unacked messages
    let remaining_unacked = buffer.unacked()?;
    tracing::info!("🔍 {} unacked messages remaining", remaining_unacked.len());
    for record in &remaining_unacked {
        let status_emoji = match record.ack_stage {
            stage if stage == constants::ack_stage::RECEIVED => "📨",
            stage if stage == constants::ack_stage::READ => "👀",
            stage if stage == constants::ack_stage::REJECTED => "❌",
            stage if stage == constants::ack_stage::FAILED => "💥",
            _ => "⏳",
        };

        tracing::info!(
            "  {} {} ({}) - stage: {}, note: '{}'",
            status_emoji,
            record.message_id,
            record.direction,
            record.ack_stage,
            record.ack_note
        );
    }

    // Show recent messages
    let recent = buffer.recent(10)?;
    tracing::info!("📝 Recent {} messages:", recent.len());
    for record in &recent {
        let age_ms = chrono::Utc::now().timestamp_millis() - record.ts_ms;
        tracing::info!(
            "  📄 {} ({}, {}ms ago) - stage: {}",
            record.message_id,
            record.direction,
            age_ms,
            record.ack_stage
        );
    }

    // Demonstrate reconciliation - find outgoing messages needing ACKs
    let reconcile = buffer.reconcile()?;
    if !reconcile.is_empty() {
        tracing::info!(
            "🔄 Found {} messages needing reconciliation",
            reconcile.len()
        );
        for record in &reconcile {
            tracing::info!(
                "  🔄 {} - sent {}ms ago, no ACK yet",
                record.message_id,
                chrono::Utc::now().timestamp_millis() - record.ts_ms
            );
        }
    } else {
        tracing::info!("✅ No messages need reconciliation");
    }

    // Force save to persistence
    buffer.flush()?;
    tracing::info!("💾 Saved activity buffer to {}", persistence_file);

    // Show file info
    if Path::new(persistence_file).exists() {
        let metadata = std::fs::metadata(persistence_file)?;
        tracing::info!(
            "📁 Persistence file: {} ({} bytes)",
            persistence_file,
            metadata.len()
        );
    }

    // Demonstrate loading from persistence
    tracing::info!("🔄 Testing persistence loading...");

    let new_persistence = Box::new(JsonFilePersistence::new(persistence_file));
    let loaded_buffer = PersistentActivityBuffer::new(100, Some(new_persistence))?;

    let loaded_recent = loaded_buffer.recent(10)?;
    tracing::info!(
        "📂 Loaded {} messages from persistence",
        loaded_recent.len()
    );

    // Clean up
    if Path::new(persistence_file).exists() {
        std::fs::remove_file(persistence_file)?;
        tracing::info!("🗑️ Cleaned up persistence file");
    }

    tracing::info!("🏁 Activity buffer demo completed!");
    Ok(())
}
