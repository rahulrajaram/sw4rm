use crate::constants::*;
use crate::envelope::EnvelopeBuilder;
use crate::{Error, Result};
use serde_json::{json, Value};

/// Build an ACK message payload
pub fn build_ack(
    ack_for_message_id: String,
    ack_stage: i32,
    error_code: i32,
    note: String,
) -> Value {
    json!({
        "ack_for_message_id": ack_for_message_id,
        "ack_stage": ack_stage,
        "error_code": error_code,
        "note": note,
    })
}

/// Build an envelope carrying an ACK payload
pub fn build_ack_envelope(
    producer_id: String,
    ack_for_message_id: String,
    ack_stage: i32,
    error_code: Option<i32>,
    note: Option<String>,
    correlation_id: Option<String>,
    sequence_number: Option<u64>,
) -> Result<crate::envelope::EnvelopeData> {
    let ack_payload = build_ack(
        ack_for_message_id,
        ack_stage,
        error_code.unwrap_or(error_code::ERROR_CODE_UNSPECIFIED),
        note.unwrap_or_default(),
    );

    let envelope = EnvelopeBuilder::new(producer_id, message_type::ACKNOWLEDGEMENT)
        .with_content_type("application/json".to_string())
        .with_json_payload(&ack_payload)?;

    let envelope = if let Some(corr_id) = correlation_id {
        envelope.with_correlation_id(corr_id)
    } else {
        envelope
    };

    let envelope = if let Some(seq) = sequence_number {
        envelope.with_sequence_number(seq)
    } else {
        envelope
    };

    Ok(envelope.build())
}

/// Map exceptions/errors to SW4RM error codes
pub fn map_error_to_error_code(error: &Error) -> i32 {
    match error {
        Error::Timeout(_) => error_code::ACK_TIMEOUT,
        Error::Connection(_) => error_code::NO_ROUTE,
        Error::InvalidEnvelope(_) => error_code::VALIDATION_ERROR,
        Error::AgentNotFound(_) => error_code::AGENT_UNAVAILABLE,
        Error::Config(_) => error_code::VALIDATION_ERROR,
        Error::Protocol(_) => error_code::VALIDATION_ERROR,
        _ => error_code::INTERNAL_ERROR,
    }
}

/// Map standard errors to SW4RM error codes
pub fn map_std_error_to_error_code(error: &dyn std::error::Error) -> i32 {
    let error_str = error.to_string().to_lowercase();
    let type_name = std::any::type_name_of_val(&error).to_lowercase();

    if error_str.contains("timeout") || type_name.contains("timeout") {
        error_code::ACK_TIMEOUT
    } else if error_str.contains("permission") || type_name.contains("permission") {
        error_code::PERMISSION_DENIED
    } else if error_str.contains("route") || error_str.contains("unavailable") {
        error_code::NO_ROUTE
    } else if error_str.contains("oversize") || error_str.contains("too large") {
        error_code::OVERSIZE_PAYLOAD
    } else if error_str.contains("validation") || error_str.contains("invalid") {
        error_code::VALIDATION_ERROR
    } else {
        error_code::INTERNAL_ERROR
    }
}

/// Helper to build an ACK envelope from a send result
pub fn ack_for_send_result(
    producer_id: String,
    original_msg_id: String,
    accepted: bool,
    reason: String,
) -> Result<crate::envelope::EnvelopeData> {
    let (stage, code) = if accepted {
        (ack_stage::FULFILLED, error_code::ERROR_CODE_UNSPECIFIED)
    } else {
        let code = if reason.is_empty() {
            error_code::ERROR_CODE_UNSPECIFIED
        } else {
            error_code::VALIDATION_ERROR
        };
        (ack_stage::REJECTED, code)
    };

    build_ack_envelope(
        producer_id,
        original_msg_id,
        stage,
        Some(code),
        Some(reason),
        None,
        None,
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_build_ack() {
        let ack = build_ack(
            "test-msg-id".to_string(),
            ack_stage::RECEIVED,
            error_code::ERROR_CODE_UNSPECIFIED,
            "test note".to_string(),
        );

        assert_eq!(ack["ack_for_message_id"], "test-msg-id");
        assert_eq!(ack["ack_stage"], ack_stage::RECEIVED);
        assert_eq!(ack["error_code"], error_code::ERROR_CODE_UNSPECIFIED);
        assert_eq!(ack["note"], "test note");
    }

    #[test]
    fn test_build_ack_envelope() {
        let envelope = build_ack_envelope(
            "producer-123".to_string(),
            "msg-456".to_string(),
            ack_stage::FULFILLED,
            None,
            Some("success".to_string()),
            None,
            None,
        )
        .unwrap();

        assert_eq!(envelope.producer_id, "producer-123");
        assert_eq!(envelope.message_type, message_type::ACKNOWLEDGEMENT);
        assert_eq!(envelope.content_type, "application/json");

        // Parse payload to verify ACK content
        let payload: Value = serde_json::from_slice(&envelope.payload).unwrap();
        assert_eq!(payload["ack_for_message_id"], "msg-456");
        assert_eq!(payload["ack_stage"], ack_stage::FULFILLED);
        assert_eq!(payload["note"], "success");
    }

    #[test]
    fn test_ack_for_send_result() {
        // Test accepted result
        let envelope = ack_for_send_result(
            "producer-1".to_string(),
            "original-msg".to_string(),
            true,
            "".to_string(),
        )
        .unwrap();

        let payload: Value = serde_json::from_slice(&envelope.payload).unwrap();
        assert_eq!(payload["ack_stage"], ack_stage::FULFILLED);
        assert_eq!(payload["error_code"], error_code::ERROR_CODE_UNSPECIFIED);

        // Test rejected result
        let envelope = ack_for_send_result(
            "producer-1".to_string(),
            "original-msg".to_string(),
            false,
            "validation failed".to_string(),
        )
        .unwrap();

        let payload: Value = serde_json::from_slice(&envelope.payload).unwrap();
        assert_eq!(payload["ack_stage"], ack_stage::REJECTED);
        assert_eq!(payload["error_code"], error_code::VALIDATION_ERROR);
    }
}
