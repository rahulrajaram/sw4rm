use serde_json::Value;
use sw4rm_sdk::compute_idempotency_token;

#[test]
fn portable_idempotency_vectors() {
    let data: Value = serde_json::from_str(include_str!(
        "../../../tests/conformance_vectors/idempotency_vectors.json"
    ))
    .unwrap();
    for vector in data["vectors"].as_array().unwrap() {
        if vector["rejected"].as_bool().unwrap_or_else(|| false) {
            // R43: LF in producer/operation must be rejected, not hashed.
            assert!(
                compute_idempotency_token(
                        vector["producer_id"].as_str().unwrap(),
                        vector["operation"].as_str().unwrap(),
                        &hex::decode(vector["canonical_hex"].as_str().unwrap()).unwrap()
                    )
                    .is_err(),
                "{}",
                vector["id"]
            );
            continue;
        }
        assert_eq!(
            compute_idempotency_token(
                vector["producer_id"].as_str().unwrap(),
                vector["operation"].as_str().unwrap(),
                &hex::decode(vector["canonical_hex"].as_str().unwrap()).unwrap()
            )
            .unwrap(),
            vector["token"].as_str().unwrap(),
            "{}",
            vector["id"]
        );
    }
}
