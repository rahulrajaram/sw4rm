use prost::Message;
use sw4rm_sdk::envelope::{EnvelopeBuilder, EnvelopeData, WireTimestamp};
use sw4rm_sdk::proto::sw4rm::common::Envelope;

#[test]
fn builder_preserves_lineage_timestamp_and_integer_precision_on_wire() {
    let mut built = EnvelopeBuilder::new("sender".into(), 2)
        .with_parent_correlation_id("parent".into())
        .with_sequence_number(u64::MAX)
        .with_payload(vec![0, 255])
        .build();
    built.timestamp = Some(WireTimestamp {
        seconds: -1,
        nanos: 125,
    });
    let proto = Envelope::from(&built);
    let decoded = Envelope::decode(proto.encode_to_vec().as_slice()).unwrap();
    let restored = EnvelopeData::from(decoded);
    assert_eq!(restored.parent_correlation_id, "parent");
    assert_eq!(
        restored.timestamp,
        Some(WireTimestamp {
            seconds: -1,
            nanos: 125
        })
    );
    assert_eq!(restored.sequence_number, u64::MAX);
    assert_eq!(restored.payload, vec![0, 255]);
}

#[test]
fn absent_timestamp_round_trips_as_absent() {
    // R9: a missing wire timestamp must not be fabricated into Some(0, 0).
    let mut built = EnvelopeBuilder::new("sender".into(), 2).build();
    built.timestamp = None;
    let proto = Envelope::from(&built);
    assert!(proto.timestamp.is_none());
    let decoded = Envelope::decode(proto.encode_to_vec().as_slice()).unwrap();
    let restored = EnvelopeData::from(decoded);
    assert!(restored.timestamp.is_none());
}

#[test]
fn decoded_stream_state_is_preserved_not_forced() {
    // R9: the wire state must survive conversion instead of being forced to
    // RECEIVED by the router stream mapping.
    use sw4rm_sdk::constants::envelope_state;
    let mut built = EnvelopeBuilder::new("sender".into(), 2).build();
    built.state = envelope_state::FULFILLED;
    let decoded = EnvelopeData::from(Envelope::from(&built));
    assert_eq!(decoded.state, envelope_state::FULFILLED);
}
