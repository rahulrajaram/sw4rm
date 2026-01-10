use crate::proto::sw4rm::policy::{EvaluationReport, NegotiationPolicy, PolicyProfile};
use crate::proto::sw4rm::scheduler::scheduler_policy_service_client::SchedulerPolicyServiceClient;
use crate::proto::sw4rm::scheduler::{
    GetEffectivePolicyRequest, GetNegotiationPolicyRequest, HitlActionRequest,
    ListPolicyProfilesRequest, SetNegotiationPolicyRequest, SetPolicyProfilesRequest,
    SubmitEvaluationRequest,
};
use crate::{Error, Result};
use tonic::transport::{Channel, Endpoint};

#[derive(Debug, Clone)]
pub struct SchedulerPolicyClient {
    client: SchedulerPolicyServiceClient<Channel>,
}

impl SchedulerPolicyClient {
    pub async fn new(endpoint: &str) -> Result<Self> {
        let channel = Endpoint::from_shared(endpoint.to_string())
            .map_err(|e| Error::Config(format!("Invalid endpoint: {}", e)))?
            .connect()
            .await?;
        Ok(Self {
            client: SchedulerPolicyServiceClient::new(channel),
        })
    }

    pub async fn set_negotiation_policy(&mut self, policy: NegotiationPolicy) -> Result<bool> {
        let req = SetNegotiationPolicyRequest {
            policy: Some(policy),
        };
        let res = self
            .client
            .set_negotiation_policy(tonic::Request::new(req))
            .await?
            .into_inner();
        Ok(res.ok)
    }

    pub async fn get_negotiation_policy(&mut self) -> Result<Option<NegotiationPolicy>> {
        let req = GetNegotiationPolicyRequest {};
        let res = self
            .client
            .get_negotiation_policy(tonic::Request::new(req))
            .await?
            .into_inner();
        Ok(res.policy)
    }

    pub async fn set_policy_profiles(&mut self, profiles: Vec<PolicyProfile>) -> Result<bool> {
        let req = SetPolicyProfilesRequest { profiles };
        let res = self
            .client
            .set_policy_profiles(tonic::Request::new(req))
            .await?
            .into_inner();
        Ok(res.ok)
    }

    pub async fn list_policy_profiles(&mut self) -> Result<Vec<PolicyProfile>> {
        let req = ListPolicyProfilesRequest {};
        let res = self
            .client
            .list_policy_profiles(tonic::Request::new(req))
            .await?
            .into_inner();
        Ok(res.profiles)
    }

    pub async fn get_effective_policy(
        &mut self,
        negotiation_id: &str,
    ) -> Result<Option<crate::proto::sw4rm::policy::EffectivePolicy>> {
        let req = GetEffectivePolicyRequest {
            negotiation_id: negotiation_id.to_string(),
        };
        let res = self
            .client
            .get_effective_policy(tonic::Request::new(req))
            .await?
            .into_inner();
        Ok(res.effective)
    }

    pub async fn submit_evaluation(
        &mut self,
        negotiation_id: &str,
        report: EvaluationReport,
    ) -> Result<bool> {
        let req = SubmitEvaluationRequest {
            negotiation_id: negotiation_id.to_string(),
            report: Some(report),
        };
        let res = self
            .client
            .submit_evaluation(tonic::Request::new(req))
            .await?
            .into_inner();
        Ok(res.accepted)
    }

    pub async fn hitl_action(
        &mut self,
        negotiation_id: &str,
        action: &str,
        rationale: &str,
    ) -> Result<bool> {
        let req = HitlActionRequest {
            negotiation_id: negotiation_id.to_string(),
            action: action.to_string(),
            rationale: rationale.to_string(),
        };
        let res = self
            .client
            .hitl_action(tonic::Request::new(req))
            .await?
            .into_inner();
        Ok(res.ok)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Test GetNegotiationPolicyRequest construction
    #[test]
    fn test_get_negotiation_policy_request() {
        let request = GetNegotiationPolicyRequest {};
        // Just verify it can be constructed (empty message)
        assert!(std::mem::size_of_val(&request) >= 0);
    }

    /// Test SetPolicyProfilesRequest with empty list
    #[test]
    fn test_set_policy_profiles_empty() {
        let request = SetPolicyProfilesRequest { profiles: vec![] };

        assert!(request.profiles.is_empty());
    }

    /// Test ListPolicyProfilesRequest construction
    #[test]
    fn test_list_policy_profiles_request() {
        let request = ListPolicyProfilesRequest {};
        // Just verify it can be constructed (empty message)
        assert!(std::mem::size_of_val(&request) >= 0);
    }

    /// Test GetEffectivePolicyRequest construction
    #[test]
    fn test_get_effective_policy_request() {
        let request = GetEffectivePolicyRequest {
            negotiation_id: "neg-123".to_string(),
        };

        assert_eq!(request.negotiation_id, "neg-123");
    }

    /// Test SubmitEvaluationRequest with no report
    #[test]
    fn test_submit_evaluation_request_no_report() {
        let request = SubmitEvaluationRequest {
            negotiation_id: "neg-123".to_string(),
            report: None,
        };

        assert_eq!(request.negotiation_id, "neg-123");
        assert!(request.report.is_none());
    }

    /// Test HitlActionRequest with all parameters
    #[test]
    fn test_hitl_action_request_all_params() {
        let request = HitlActionRequest {
            negotiation_id: "neg-123".to_string(),
            action: "approve".to_string(),
            rationale: "Looks good to me".to_string(),
        };

        assert_eq!(request.negotiation_id, "neg-123");
        assert_eq!(request.action, "approve");
        assert_eq!(request.rationale, "Looks good to me");
    }

    /// Test HitlActionRequest with default rationale
    #[test]
    fn test_hitl_action_request_default_rationale() {
        let request = HitlActionRequest {
            negotiation_id: "neg-123".to_string(),
            action: "reject".to_string(),
            rationale: String::new(),
        };

        assert!(request.rationale.is_empty());
    }

    /// Test HitlActionRequest approve action
    #[test]
    fn test_hitl_action_approve() {
        let request = HitlActionRequest {
            negotiation_id: "neg-123".to_string(),
            action: "approve".to_string(),
            rationale: "Approved".to_string(),
        };

        assert_eq!(request.action, "approve");
    }

    /// Test HitlActionRequest reject action
    #[test]
    fn test_hitl_action_reject() {
        let request = HitlActionRequest {
            negotiation_id: "neg-123".to_string(),
            action: "reject".to_string(),
            rationale: "Policy violation".to_string(),
        };

        assert_eq!(request.action, "reject");
        assert_eq!(request.rationale, "Policy violation");
    }

    /// Test multiple negotiations handling (request structures)
    #[test]
    fn test_multiple_negotiations() {
        let requests: Vec<GetEffectivePolicyRequest> = vec!["neg-1", "neg-2", "neg-3"]
            .into_iter()
            .map(|id| GetEffectivePolicyRequest {
                negotiation_id: id.to_string(),
            })
            .collect();

        assert_eq!(requests.len(), 3);
        assert_eq!(requests[0].negotiation_id, "neg-1");
        assert_eq!(requests[1].negotiation_id, "neg-2");
        assert_eq!(requests[2].negotiation_id, "neg-3");
    }

    /// Test request structures in sequence
    #[test]
    fn test_request_sequence() {
        // Get effective policy
        let effective_request = GetEffectivePolicyRequest {
            negotiation_id: "neg-1".to_string(),
        };
        assert!(!effective_request.negotiation_id.is_empty());

        // Submit evaluation
        let eval_request = SubmitEvaluationRequest {
            negotiation_id: "neg-1".to_string(),
            report: None,
        };
        assert!(!eval_request.negotiation_id.is_empty());

        // HITL action
        let hitl_request = HitlActionRequest {
            negotiation_id: "neg-1".to_string(),
            action: "approve".to_string(),
            rationale: String::new(),
        };
        assert_eq!(hitl_request.action, "approve");
    }
}
