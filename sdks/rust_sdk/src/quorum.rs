//! Runtime-neutral quorum policy evaluation.
//!
//! This module mirrors `sw4rm_policies.quorum`: policies are immutable
//! descriptions and [`evaluate`] is a pure function over collected votes.

use crate::clients::negotiation_room::NegotiationVote;
use crate::{Error, Result};
use std::collections::HashSet;

/// Require at least `n` distinct requested critics.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct MinimumVotes {
    pub n: usize,
}

impl MinimumVotes {
    pub const fn new(n: usize) -> Self {
        Self { n }
    }
}

/// Require the ceiling of expected critics times `fraction`.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct MinimumFraction {
    pub fraction: f64,
}

impl MinimumFraction {
    pub const fn new(fraction: f64) -> Self {
        Self { fraction }
    }
}

/// Require every requested critic when enabled.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct RequireAll {
    pub enabled: bool,
}

impl RequireAll {
    pub const fn new(enabled: bool) -> Self {
        Self { enabled }
    }
}

/// A quorum threshold rule.
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum QuorumRule {
    MinimumVotes(MinimumVotes),
    MinimumFraction(MinimumFraction),
    RequireAll(RequireAll),
}

/// Action to take when a quorum is not met.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FailureAction {
    /// Escalate to human review (`fail_closed`).
    FailClosed,
    /// Decide with generated abstain votes (`fail_with_abstain`).
    FailWithAbstain,
    /// Decide with the votes that were received (`fail_with_available`).
    FailWithAvailable,
}

impl FailureAction {
    /// Parse the Python policy action names.
    pub fn from_name(name: &str) -> Option<Self> {
        match name {
            "fail_closed" => Some(Self::FailClosed),
            "fail_with_abstain" => Some(Self::FailWithAbstain),
            "fail_with_available" => Some(Self::FailWithAvailable),
            _ => None,
        }
    }
}

/// Immutable pairing of a quorum rule and failure action.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct QuorumPolicy {
    pub rule: QuorumRule,
    pub on_failure: FailureAction,
}

impl QuorumPolicy {
    pub const fn new(rule: QuorumRule, on_failure: FailureAction) -> Self {
        Self { rule, on_failure }
    }
}

/// Human-review escalation failure outcome.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct EscalateHitl {
    pub reason: String,
}

/// Generated abstain vote for a requested critic that did not vote.
#[derive(Debug, Clone, PartialEq)]
pub struct AbstainVote {
    pub critic_id: String,
    pub score: f64,
    pub confidence: f64,
    pub passed: bool,
    pub abstain: bool,
}

/// Failure action carrying generated abstain records.
#[derive(Debug, Clone, PartialEq)]
pub struct DecidedWithAbstains {
    pub injected_votes: Vec<AbstainVote>,
}

/// Failure action that permits deciding from the votes received so far.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct DecidedWithAvailable;

/// Failure outcome returned when quorum is not met.
#[derive(Debug, Clone, PartialEq)]
pub enum QuorumFailure {
    EscalateHitl(EscalateHitl),
    DecidedWithAbstains(DecidedWithAbstains),
    DecidedWithAvailable(DecidedWithAvailable),
}

/// Result of evaluating a quorum policy.
#[derive(Debug, Clone, PartialEq)]
pub struct QuorumOutcome<V> {
    pub met: bool,
    pub votes_received: usize,
    pub votes_expected: usize,
    pub threshold: usize,
    pub action: Option<QuorumFailure>,
    /// Number of original votes plus generated abstains, matching Python's
    /// downstream `all_votes` cardinality.
    pub all_vote_count: usize,
    /// Original input votes, preserved without injected records.
    pub all_votes: Vec<V>,
}

/// Extracts the critic identity used for distinct-vote counting.
pub trait CriticId {
    fn critic_id(&self) -> &str;
}

impl CriticId for NegotiationVote {
    fn critic_id(&self) -> &str {
        &self.critic_id
    }
}

impl CriticId for String {
    fn critic_id(&self) -> &str {
        self
    }
}

impl CriticId for str {
    fn critic_id(&self) -> &str {
        self
    }
}

/// Return the majority, fail-closed default policy.
pub const fn default_policy() -> QuorumPolicy {
    QuorumPolicy::new(
        QuorumRule::MinimumFraction(MinimumFraction::new(0.5)),
        FailureAction::FailClosed,
    )
}

fn compute_threshold(rule: QuorumRule, expected: usize) -> Result<usize> {
    match rule {
        QuorumRule::MinimumVotes(rule) => Ok(rule.n),
        QuorumRule::MinimumFraction(rule) => {
            if !rule.fraction.is_finite() || rule.fraction < 0.0 {
                return Err(Error::Config(format!(
                    "quorum fraction must be finite and non-negative, got {}",
                    rule.fraction
                )));
            }
            let threshold = (expected as f64 * rule.fraction).ceil();
            if threshold > usize::MAX as f64 {
                return Err(Error::Config("quorum threshold is too large".to_string()));
            }
            Ok(threshold as usize)
        }
        QuorumRule::RequireAll(rule) => Ok(if rule.enabled { expected } else { 0 }),
    }
}

/// Evaluate collected votes against a policy.
pub fn evaluate<V, S>(
    votes: &[V],
    requested_critics: &[S],
    policy: QuorumPolicy,
) -> Result<QuorumOutcome<V>>
where
    V: CriticId + Clone,
    S: AsRef<str>,
{
    let voted_ids: HashSet<&str> = votes.iter().map(CriticId::critic_id).collect();
    let requested_ids: HashSet<&str> = requested_critics.iter().map(AsRef::as_ref).collect();
    let expected = requested_critics.len();
    let received = voted_ids.intersection(&requested_ids).count();
    let threshold = compute_threshold(policy.rule, expected)?;
    let all_votes = votes.to_vec();

    if received >= threshold {
        return Ok(QuorumOutcome {
            met: true,
            votes_received: received,
            votes_expected: expected,
            threshold,
            action: None,
            all_vote_count: all_votes.len(),
            all_votes,
        });
    }

    let action = match policy.on_failure {
        FailureAction::FailClosed => QuorumFailure::EscalateHitl(EscalateHitl {
            reason: "Quorum not met — escalating to HITL".to_string(),
        }),
        FailureAction::FailWithAbstain => QuorumFailure::DecidedWithAbstains(DecidedWithAbstains {
            injected_votes: requested_critics
                .iter()
                .filter(|critic| !voted_ids.contains(critic.as_ref()))
                .map(|critic_id| AbstainVote {
                    critic_id: critic_id.as_ref().to_string(),
                    score: 0.0,
                    confidence: 0.0,
                    passed: false,
                    abstain: true,
                })
                .collect(),
        }),
        FailureAction::FailWithAvailable => {
            QuorumFailure::DecidedWithAvailable(DecidedWithAvailable)
        }
    };
    let all_vote_count = all_votes.len()
        + match &action {
            QuorumFailure::DecidedWithAbstains(action) => action.injected_votes.len(),
            _ => 0,
        };

    Ok(QuorumOutcome {
        met: false,
        votes_received: received,
        votes_expected: expected,
        threshold,
        action: Some(action),
        all_vote_count,
        all_votes,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[derive(Clone)]
    struct Vote(&'static str);

    impl CriticId for Vote {
        fn critic_id(&self) -> &str {
            self.0
        }
    }

    fn critics(ids: &[&str]) -> Vec<String> {
        ids.iter().map(|id| (*id).to_string()).collect()
    }

    #[test]
    fn counts_only_distinct_requested_critics() {
        let votes = vec![Vote("a"), Vote("a"), Vote("outside")];
        let outcome = evaluate(
            &votes,
            &critics(&["a", "b"]),
            QuorumPolicy::new(
                QuorumRule::MinimumVotes(MinimumVotes::new(2)),
                FailureAction::FailClosed,
            ),
        )
        .unwrap();
        assert!(!outcome.met);
        assert_eq!(outcome.votes_received, 1);
        assert_eq!(outcome.threshold, 2);
    }

    #[test]
    fn fraction_is_ceiled_and_abstains_preserve_request_order() {
        let votes = vec![Vote("a")];
        let outcome = evaluate(
            &votes,
            &critics(&["a", "b", "c"]),
            QuorumPolicy::new(
                QuorumRule::MinimumFraction(MinimumFraction::new(0.5)),
                FailureAction::FailWithAbstain,
            ),
        )
        .unwrap();
        assert_eq!(outcome.threshold, 2);
        match outcome.action.unwrap() {
            QuorumFailure::DecidedWithAbstains(DecidedWithAbstains { injected_votes }) => {
                assert_eq!(
                    injected_votes
                        .into_iter()
                        .map(|vote| vote.critic_id)
                        .collect::<Vec<_>>(),
                    vec!["b", "c"]
                );
            }
            action => panic!("unexpected action: {action:?}"),
        }
    }

    #[test]
    fn disabled_require_all_met_with_no_votes() {
        let outcome: QuorumOutcome<Vote> = evaluate(
            &[],
            &critics(&["a"]),
            QuorumPolicy::new(
                QuorumRule::RequireAll(RequireAll::new(false)),
                FailureAction::FailClosed,
            ),
        )
        .unwrap();
        assert!(outcome.met);
        assert_eq!(outcome.threshold, 0);
    }
}
