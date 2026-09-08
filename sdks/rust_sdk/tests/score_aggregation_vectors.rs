use serde::Deserialize;
use sw4rm_sdk::clients::negotiation_room::NegotiationVote;
use sw4rm_sdk::voting::aggregate_votes;

#[derive(Debug, Deserialize)]
struct ScoreAggregationSuite {
    vectors: Vec<ScoreAggregationVector>,
}

#[derive(Debug, Deserialize)]
struct ScoreAggregationVector {
    id: String,
    votes: Vec<ScoreVote>,
    expected: Option<ExpectedScore>,
    error: Option<String>,
}

#[derive(Debug, Deserialize)]
struct ScoreVote {
    score: f64,
    confidence: f64,
}

#[derive(Debug, Deserialize)]
struct ExpectedScore {
    mean: f64,
    min_score: f64,
    max_score: f64,
    std_dev: f64,
    weighted_mean: f64,
    vote_count: usize,
}

fn load_vectors() -> ScoreAggregationSuite {
    serde_json::from_str(include_str!(
        "../../../tests/conformance_vectors/score_aggregation_vectors.json"
    ))
    .expect("shared score aggregation vectors should parse")
}

#[test]
fn shared_score_aggregation_conformance_vectors() {
    for vector in load_vectors().vectors {
        let votes: Vec<_> = vector
            .votes
            .iter()
            .enumerate()
            .map(|(index, vote)| {
                NegotiationVote::new(
                    format!("artifact-{}", vector.id),
                    format!("critic-{index}"),
                    vote.score,
                    vote.confidence,
                    true,
                    Vec::new(),
                    Vec::new(),
                    Vec::new(),
                    format!("room-{}", vector.id),
                )
                .expect("vector vote should satisfy NegotiationVote constraints")
            })
            .collect();

        match vector.error.as_deref() {
            Some("empty-votes") => {
                assert!(
                    aggregate_votes(&votes).is_err(),
                    "vector '{}' should reject empty input",
                    vector.id
                );
            }
            Some(other) => panic!("vector '{}' has unsupported error: {other}", vector.id),
            None => {
                let expected = vector
                    .expected
                    .as_ref()
                    .expect("successful vector should provide expected values");
                let actual = aggregate_votes(&votes)
                    .unwrap_or_else(|error| panic!("vector '{}' failed: {error}", vector.id));
                let close = |name: &str, actual: f64, expected: f64| {
                    assert!(
                        (actual - expected).abs() < 1e-9,
                        "vector '{}' {name}: actual={actual}, expected={expected}",
                        vector.id
                    );
                };
                close("mean", actual.mean, expected.mean);
                close("min_score", actual.min_score, expected.min_score);
                close("max_score", actual.max_score, expected.max_score);
                close("std_dev", actual.std_dev, expected.std_dev);
                close(
                    "weighted_mean",
                    actual.weighted_mean,
                    expected.weighted_mean,
                );
                assert_eq!(actual.vote_count, expected.vote_count);
            }
        }
    }
}
