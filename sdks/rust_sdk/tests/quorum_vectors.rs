use serde::Deserialize;
use sw4rm_sdk::quorum::{
    evaluate, CriticId, DecidedWithAbstains, FailureAction, MinimumFraction, MinimumVotes,
    QuorumFailure, QuorumPolicy, QuorumRule, RequireAll,
};

#[derive(Debug, Clone, Deserialize)]
struct Suite {
    vectors: Vec<Vector>,
}

#[derive(Debug, Clone, Deserialize)]
struct Vector {
    id: String,
    requested: Vec<String>,
    votes: Vec<Vote>,
    rule: Rule,
    on_failure: String,
    expected: Expected,
}

#[derive(Debug, Clone, Deserialize)]
struct Vote {
    critic_id: String,
}

impl CriticId for Vote {
    fn critic_id(&self) -> &str {
        &self.critic_id
    }
}

#[derive(Debug, Clone, Deserialize)]
struct Rule {
    kind: String,
    value: serde_json::Value,
}

#[derive(Debug, Clone, Deserialize)]
struct Expected {
    met: bool,
    received: usize,
    expected: usize,
    threshold: usize,
    action: String,
    injected: Vec<String>,
    all_vote_count: usize,
}

fn load_vectors() -> Suite {
    serde_json::from_str(include_str!(
        "../../../tests/conformance_vectors/quorum_vectors.json"
    ))
    .expect("shared quorum vectors should parse")
}

fn rule_from_vector(rule: &Rule) -> QuorumRule {
    match rule.kind.as_str() {
        "minimum_votes" => QuorumRule::MinimumVotes(MinimumVotes::new(
            rule.value
                .as_u64()
                .expect("minimum_votes value should be an integer") as usize,
        )),
        "minimum_fraction" => QuorumRule::MinimumFraction(MinimumFraction::new(
            rule.value
                .as_f64()
                .expect("minimum_fraction value should be a number"),
        )),
        "require_all" => QuorumRule::RequireAll(RequireAll::new(
            rule.value
                .as_bool()
                .expect("require_all value should be boolean"),
        )),
        other => panic!("unsupported quorum rule: {other}"),
    }
}

#[test]
fn shared_quorum_conformance_vectors() {
    for vector in load_vectors().vectors {
        let action = FailureAction::from_name(&vector.on_failure)
            .unwrap_or_else(|| panic!("vector '{}' has unsupported action", vector.id));
        let outcome = evaluate(
            &vector.votes,
            &vector.requested,
            QuorumPolicy::new(rule_from_vector(&vector.rule), action),
        )
        .unwrap_or_else(|error| panic!("vector '{}' failed: {error}", vector.id));

        assert_eq!(outcome.met, vector.expected.met, "{} met", vector.id);
        assert_eq!(
            outcome.votes_received, vector.expected.received,
            "{} received",
            vector.id
        );
        assert_eq!(
            outcome.votes_expected, vector.expected.expected,
            "{} expected",
            vector.id
        );
        assert_eq!(
            outcome.threshold, vector.expected.threshold,
            "{} threshold",
            vector.id
        );
        assert_eq!(
            outcome.all_vote_count, vector.expected.all_vote_count,
            "{} count",
            vector.id
        );

        match (vector.expected.action.as_str(), outcome.action) {
            ("none", None) => {}
            ("escalate_hitl", Some(QuorumFailure::EscalateHitl(_))) => {}
            ("decided_with_available", Some(QuorumFailure::DecidedWithAvailable(_))) => {}
            (
                "decided_with_abstains",
                Some(QuorumFailure::DecidedWithAbstains(DecidedWithAbstains { injected_votes })),
            ) => {
                assert_eq!(
                    injected_votes
                        .into_iter()
                        .map(|vote| vote.critic_id)
                        .collect::<Vec<_>>(),
                    vector.expected.injected
                );
            }
            (expected, actual) => panic!(
                "vector '{}' action mismatch: expected {expected}, got {actual:?}",
                vector.id
            ),
        }
    }
}
