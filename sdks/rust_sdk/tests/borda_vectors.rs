//! Cross-SDK Borda conformance vectors (R22).
//!
//! Pins identical score-derived Borda outputs across the Python, JavaScript,
//! and Rust SDKs. The Lisp and Elixir SDKs implement classic Borda over
//! ranked preference lists (a distinct input format) and are intentionally
//! not part of this scored-vote corpus.

use chrono::{TimeZone, Utc};
use serde_json::Value;
use sw4rm_sdk::clients::negotiation_room::{AggregatedScore, NegotiationVote};
use sw4rm_sdk::{AggregationStrategy, BordaCountAggregator};

fn vectors() -> Vec<Value> {
    serde_json::from_str::<Value>(include_str!(
        "../../../tests/conformance_vectors/borda_vectors.json"
    ))
    .unwrap()["vectors"]
        .as_array()
        .unwrap()
        .clone()
}

fn vote(entry: &Value) -> NegotiationVote {
    NegotiationVote {
        artifact_id: "conformance".to_string(),
        critic_id: entry["critic_id"].as_str().unwrap().to_string(),
        score: entry["score"].as_f64().unwrap(),
        confidence: 1.0,
        passed: true,
        strengths: vec![],
        weaknesses: vec![],
        recommendations: vec![],
        negotiation_room_id: String::new(),
        voted_at: Utc.timestamp_opt(0, 0).single().unwrap(),
    }
}

fn assert_close(label: &str, actual: f64, expected: f64) {
    assert!(
        (actual - expected).abs() < 1e-9,
        "{label}: actual {actual} vs expected {expected}"
    );
}

#[test]
fn borda_conformance_vectors() {
    let aggregator = BordaCountAggregator;
    for vector in vectors() {
        let votes: Vec<NegotiationVote> = vector["votes"]
            .as_array()
            .unwrap()
            .iter()
            .map(vote)
            .collect();
        let outcome: AggregatedScore = aggregator.aggregate(&votes).unwrap();
        let expected = &vector["expected"];
        assert_close(
            &format!("{} weighted_mean", vector["id"].as_str().unwrap()),
            outcome.weighted_mean,
            expected["weighted_mean"].as_f64().unwrap(),
        );
        assert_close(
            &format!("{} mean", vector["id"].as_str().unwrap()),
            outcome.mean,
            expected["mean"].as_f64().unwrap(),
        );
        assert_close(
            &format!("{} std_dev", vector["id"].as_str().unwrap()),
            outcome.std_dev,
            expected["std_dev"].as_f64().unwrap(),
        );
        assert_close(
            &format!("{} min_score", vector["id"].as_str().unwrap()),
            outcome.min_score,
            expected["min_score"].as_f64().unwrap(),
        );
        assert_close(
            &format!("{} max_score", vector["id"].as_str().unwrap()),
            outcome.max_score,
            expected["max_score"].as_f64().unwrap(),
        );
        assert_eq!(
            outcome.vote_count,
            expected["vote_count"].as_u64().unwrap() as usize,
            "{}",
            vector["id"].as_str().unwrap()
        );
    }
}

#[test]
fn borda_output_depends_on_scores_not_just_count() {
    // Same vote count, different scores -> different output (R22 regression).
    let aggregator = BordaCountAggregator;
    let votes_for = |scores: &[f64]| -> Vec<NegotiationVote> {
        scores
            .iter()
            .enumerate()
            .map(|(i, &score)| {
                vote(&serde_json::json!({"critic_id": format!("c{i}"), "score": score}))
            })
            .collect()
    };
    let high = aggregator.aggregate(&votes_for(&[9.0, 9.0, 9.0])).unwrap();
    let low = aggregator.aggregate(&votes_for(&[1.0, 1.0, 1.0])).unwrap();
    assert_eq!(high.vote_count, low.vote_count);
    assert_ne!(high.weighted_mean, low.weighted_mean);
}
