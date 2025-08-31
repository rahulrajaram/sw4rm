//! Test to verify protobuf compilation and code generation works correctly

use sw4rm_sdk::proto;

#[test]
fn test_proto_module_exists() {
    // This test verifies that the proto module can be imported
    // If protobuf compilation failed, this would fail to compile
    let _proto_ref = &proto::sw4rm::common::MessageType::Data;
}

#[test]
fn test_envelope_struct_exists() {
    // Test that we can create an envelope struct
    let envelope = proto::sw4rm::common::Envelope {
        message_id: "test".to_string(),
        idempotency_token: String::new(),
        producer_id: "test-producer".to_string(),
        correlation_id: String::new(),
        sequence_number: 1,
        retry_count: 0,
        message_type: proto::sw4rm::common::MessageType::Data as i32,
        content_type: "application/octet-stream".to_string(),
        content_length: 3,
        repo_id: String::new(),
        worktree_id: String::new(),
        hlc_timestamp: String::new(),
        ttl_ms: 0,
        timestamp: None,
        payload: vec![1, 2, 3],
    };

    assert_eq!(envelope.message_id, "test");
    assert_eq!(envelope.producer_id, "test-producer");
    assert_eq!(
        envelope.message_type,
        proto::sw4rm::common::MessageType::Data as i32
    );
}

#[cfg(feature = "proto")]
#[tokio::test]
async fn test_registry_client_creation() {
    // Test that we can create a registry client (even if we can't connect)
    use tonic::transport::Endpoint;

    // This should compile but will fail at runtime due to no server
    let endpoint = Endpoint::from_static("http://localhost:50051");
    let result = endpoint.connect_lazy();

    let _client =
        proto::sw4rm::registry::registry_service_client::RegistryServiceClient::new(result);
    // Just testing that the client type exists and can be constructed
}

#[test]
fn test_message_type_values() {
    // Verify message type constants match expected values
    use proto::sw4rm::common::MessageType;

    assert_eq!(MessageType::Control as i32, 1);
    assert_eq!(MessageType::Data as i32, 2);
    assert_eq!(MessageType::Acknowledgement as i32, 5);
}

#[test]
fn test_proto_compilation_integration() {
    // Integration test to verify all major proto types compile
    use proto::sw4rm;

    // Test common types
    let _envelope = sw4rm::common::Envelope {
        message_id: String::new(),
        idempotency_token: String::new(),
        producer_id: String::new(),
        correlation_id: String::new(),
        sequence_number: 0,
        retry_count: 0,
        message_type: 0,
        content_type: String::new(),
        content_length: 0,
        repo_id: String::new(),
        worktree_id: String::new(),
        hlc_timestamp: String::new(),
        ttl_ms: 0,
        timestamp: None,
        payload: Vec::new(),
    };

    // Test that client modules exist
    let _registry_exists = std::mem::size_of::<sw4rm::registry::RegisterAgentRequest>();

    // This test passing means protobuf compilation succeeded
    // Test would fail at compile-time if protos are broken
}
