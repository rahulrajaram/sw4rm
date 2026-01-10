use crate::proto::sw4rm::hitl::hitl_service_client::HitlServiceClient;
use crate::proto::sw4rm::hitl::HitlInvocation;
use crate::{Error, Result};
use tonic::transport::{Channel, Endpoint};

/// Client for interacting with the SW4RM Human-in-the-Loop service
#[derive(Debug, Clone)]
pub struct HitlClient {
    client: HitlServiceClient<Channel>,
}

impl HitlClient {
    /// Create a new HITL client
    pub async fn new(endpoint: &str) -> Result<Self> {
        let channel = Endpoint::from_shared(endpoint.to_string())
            .map_err(|e| Error::Config(format!("Invalid endpoint: {}", e)))?
            .connect()
            .await?;

        Ok(Self {
            client: HitlServiceClient::new(channel),
        })
    }

    /// Send a decision request to human operator
    pub async fn decide(
        &mut self,
        reason_type: i32,
        context: Vec<u8>,
        proposed_actions: Vec<String>,
        priority: i32,
    ) -> Result<HitlDecisionResponse> {
        let invocation = HitlInvocation {
            reason_type,
            context,
            proposed_actions,
            priority,
        };

        let request = tonic::Request::new(invocation);

        let response = self.client.decide(request).await?;
        let decision = response.into_inner();

        Ok(HitlDecisionResponse {
            action: decision.action,
            decision_payload: decision.decision_payload,
            rationale: decision.rationale,
        })
    }
}

/// Response from a HITL decision request
#[derive(Debug, Clone)]
pub struct HitlDecisionResponse {
    pub action: String,
    pub decision_payload: Vec<u8>,
    pub rationale: String,
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Test HitlInvocation construction with all parameters
    #[test]
    fn test_hitl_invocation_construction() {
        let invocation = HitlInvocation {
            reason_type: 1,
            context: b"Need human review".to_vec(),
            proposed_actions: vec!["approve".to_string(), "reject".to_string()],
            priority: 5,
        };

        assert_eq!(invocation.reason_type, 1);
        assert_eq!(invocation.context, b"Need human review");
        assert_eq!(invocation.proposed_actions.len(), 2);
        assert_eq!(invocation.priority, 5);
    }

    /// Test HitlInvocation with minimal fields
    #[test]
    fn test_hitl_invocation_minimal() {
        let invocation = HitlInvocation {
            reason_type: 0,
            context: vec![],
            proposed_actions: vec![],
            priority: 0,
        };

        assert_eq!(invocation.reason_type, 0);
        assert!(invocation.context.is_empty());
        assert!(invocation.proposed_actions.is_empty());
        assert_eq!(invocation.priority, 0);
    }

    /// Test HitlInvocation with multiple options
    #[test]
    fn test_hitl_invocation_multiple_options() {
        let invocation = HitlInvocation {
            reason_type: 2, // HIGH_RISK_OPERATION
            context: b"Risky transaction".to_vec(),
            proposed_actions: vec![
                "approve".to_string(),
                "reject".to_string(),
                "modify".to_string(),
                "escalate_to_manager".to_string(),
            ],
            priority: 10,
        };

        assert_eq!(invocation.proposed_actions.len(), 4);
        assert!(invocation.proposed_actions.contains(&"approve".to_string()));
        assert!(invocation.proposed_actions.contains(&"escalate_to_manager".to_string()));
    }

    /// Test HitlInvocation with rich context
    #[test]
    fn test_hitl_invocation_rich_context() {
        let context_json = serde_json::json!({
            "amount": 10000,
            "currency": "USD",
            "requester": "user-123",
            "threshold_exceeded": true
        });
        let context_bytes = serde_json::to_vec(&context_json).unwrap();

        let invocation = HitlInvocation {
            reason_type: 3, // POLICY_REQUIRES_HUMAN_APPROVAL
            context: context_bytes.clone(),
            proposed_actions: vec!["approve".to_string(), "reject".to_string()],
            priority: 8,
        };

        assert!(!invocation.context.is_empty());
        // Verify we can deserialize the context
        let parsed: serde_json::Value = serde_json::from_slice(&invocation.context).unwrap();
        assert_eq!(parsed["amount"], 10000);
        assert_eq!(parsed["currency"], "USD");
    }

    /// Test HitlDecisionResponse construction
    #[test]
    fn test_hitl_decision_response_construction() {
        let response = HitlDecisionResponse {
            action: "approve".to_string(),
            decision_payload: b"approved by manager".to_vec(),
            rationale: "Verified by security team".to_string(),
        };

        assert_eq!(response.action, "approve");
        assert_eq!(response.decision_payload, b"approved by manager");
        assert_eq!(response.rationale, "Verified by security team");
    }

    /// Test HitlDecisionResponse with empty payload
    #[test]
    fn test_hitl_decision_response_empty_payload() {
        let response = HitlDecisionResponse {
            action: "reject".to_string(),
            decision_payload: vec![],
            rationale: "Denied".to_string(),
        };

        assert!(response.decision_payload.is_empty());
    }

    /// Test different reason types
    #[test]
    fn test_different_reason_types() {
        let reason_types = vec![
            (0, "UNSPECIFIED"),
            (1, "LOW_CONFIDENCE"),
            (2, "HIGH_RISK_OPERATION"),
            (3, "POLICY_REQUIRES_HUMAN_APPROVAL"),
            (4, "ANOMALY_DETECTED"),
        ];

        for (code, _name) in reason_types {
            let invocation = HitlInvocation {
                reason_type: code,
                context: vec![],
                proposed_actions: vec![],
                priority: 0,
            };
            assert_eq!(invocation.reason_type, code);
        }
    }

    /// Test multiple HITL invocations
    #[test]
    fn test_multiple_invocations() {
        let invocations: Vec<HitlInvocation> = (0..3)
            .map(|i| HitlInvocation {
                reason_type: 1, // LOW_CONFIDENCE
                context: format!("Context for invocation {}", i).into_bytes(),
                proposed_actions: vec!["approve".to_string(), "reject".to_string()],
                priority: i,
            })
            .collect();

        assert_eq!(invocations.len(), 3);
        assert_eq!(invocations[0].priority, 0);
        assert_eq!(invocations[1].priority, 1);
        assert_eq!(invocations[2].priority, 2);
    }

    /// Test priority levels
    #[test]
    fn test_priority_levels() {
        // Test low priority
        let low_priority = HitlInvocation {
            reason_type: 1,
            context: vec![],
            proposed_actions: vec![],
            priority: 1,
        };
        assert_eq!(low_priority.priority, 1);

        // Test medium priority
        let medium_priority = HitlInvocation {
            reason_type: 1,
            context: vec![],
            proposed_actions: vec![],
            priority: 5,
        };
        assert_eq!(medium_priority.priority, 5);

        // Test high priority
        let high_priority = HitlInvocation {
            reason_type: 1,
            context: vec![],
            proposed_actions: vec![],
            priority: 10,
        };
        assert_eq!(high_priority.priority, 10);
    }

    /// Test HitlDecisionResponse clone
    #[test]
    fn test_hitl_decision_response_clone() {
        let response = HitlDecisionResponse {
            action: "approve".to_string(),
            decision_payload: b"data".to_vec(),
            rationale: "reason".to_string(),
        };

        let cloned = response.clone();
        assert_eq!(response.action, cloned.action);
        assert_eq!(response.decision_payload, cloned.decision_payload);
        assert_eq!(response.rationale, cloned.rationale);
    }

    /// Test HitlDecisionResponse debug
    #[test]
    fn test_hitl_decision_response_debug() {
        let response = HitlDecisionResponse {
            action: "approve".to_string(),
            decision_payload: vec![],
            rationale: "OK".to_string(),
        };

        let debug_str = format!("{:?}", response);
        assert!(debug_str.contains("HitlDecisionResponse"));
        assert!(debug_str.contains("approve"));
    }

    /// Test binary context data
    #[test]
    fn test_binary_context() {
        let binary_data: Vec<u8> = vec![0x00, 0x01, 0x02, 0xff, 0xfe, 0xfd];

        let invocation = HitlInvocation {
            reason_type: 1,
            context: binary_data.clone(),
            proposed_actions: vec![],
            priority: 0,
        };

        assert_eq!(invocation.context, binary_data);
    }
}
