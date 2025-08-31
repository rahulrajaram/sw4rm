use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "kind")]
pub enum NegotiationEvent {
    #[serde(rename = "open")]
    Open {
        ts: Option<String>,
        topic: String,
        corr: String,
    },
    #[serde(rename = "policy")]
    Policy {
        ts: Option<String>,
        negotiation_id: String,
        profile: Option<String>,
        policy: serde_json::Value,
    },
    #[serde(rename = "propose")]
    Propose {
        ts: Option<String>,
        from: String,
        ct: String,
        payload_b64: Option<String>,
    },
    #[serde(rename = "counter")]
    Counter {
        ts: Option<String>,
        from: String,
        ct: String,
        payload_b64: Option<String>,
    },
    #[serde(rename = "evaluate")]
    Evaluate {
        ts: Option<String>,
        from: String,
        score: Option<f64>,
        notes: Option<String>,
    },
    #[serde(rename = "decide")]
    Decide {
        ts: Option<String>,
        by: String,
        ct: String,
        result_b64: Option<String>,
    },
    #[serde(rename = "abort")]
    Abort {
        ts: Option<String>,
        reason: Option<String>,
    },
    #[serde(other)]
    Unknown,
}

pub fn parse_negotiation_event(raw: &[u8]) -> Option<NegotiationEvent> {
    serde_json::from_slice::<NegotiationEvent>(raw).ok()
}

pub fn decode_b64(s: &Option<String>) -> Option<Vec<u8>> {
    use base64::engine::general_purpose::STANDARD;
    use base64::Engine;
    s.as_ref().and_then(|b| STANDARD.decode(b).ok())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_policy_event() {
        let json = r#"{"kind":"policy","negotiation_id":"neg-1","policy":{"max_rounds":4}}"#;
        let evt = parse_negotiation_event(json.as_bytes()).unwrap();
        match evt {
            NegotiationEvent::Policy { negotiation_id, .. } => assert_eq!(negotiation_id, "neg-1"),
            _ => panic!("expected policy"),
        }
    }

    #[test]
    fn decode_payload_b64() {
        let s = Some("SGk=".to_string());
        let bytes = decode_b64(&s).unwrap();
        assert_eq!(String::from_utf8(bytes).unwrap(), "Hi");
    }
}
