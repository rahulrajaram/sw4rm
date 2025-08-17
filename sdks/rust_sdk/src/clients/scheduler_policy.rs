use crate::proto::sw4rm::scheduler::scheduler_policy_service_client::SchedulerPolicyServiceClient;
use crate::proto::sw4rm::scheduler::{
    SetWagglePolicyRequest, GetWagglePolicyRequest,
    SetPolicyProfilesRequest, ListPolicyProfilesRequest,
    GetEffectivePolicyRequest, SubmitEvaluationRequest,
    HitlActionRequest,
};
use crate::proto::sw4rm::policy::{WagglePolicy, PolicyProfile, EvaluationReport};
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
        Ok(Self { client: SchedulerPolicyServiceClient::new(channel) })
    }

    pub async fn set_waggle_policy(&mut self, policy: WagglePolicy) -> Result<bool> {
        let req = SetWagglePolicyRequest { policy: Some(policy) };
        let res = self.client.set_waggle_policy(tonic::Request::new(req)).await?.into_inner();
        Ok(res.ok)
    }

    pub async fn get_waggle_policy(&mut self) -> Result<Option<WagglePolicy>> {
        let req = GetWagglePolicyRequest {};
        let res = self.client.get_waggle_policy(tonic::Request::new(req)).await?.into_inner();
        Ok(res.policy)
    }

    pub async fn set_policy_profiles(&mut self, profiles: Vec<PolicyProfile>) -> Result<bool> {
        let req = SetPolicyProfilesRequest { profiles };
        let res = self.client.set_policy_profiles(tonic::Request::new(req)).await?.into_inner();
        Ok(res.ok)
    }

    pub async fn list_policy_profiles(&mut self) -> Result<Vec<PolicyProfile>> {
        let req = ListPolicyProfilesRequest {};
        let res = self.client.list_policy_profiles(tonic::Request::new(req)).await?.into_inner();
        Ok(res.profiles)
    }

    pub async fn get_effective_policy(&mut self, negotiation_id: &str) -> Result<Option<crate::proto::sw4rm::policy::EffectivePolicy>> {
        let req = GetEffectivePolicyRequest { negotiation_id: negotiation_id.to_string() };
        let res = self.client.get_effective_policy(tonic::Request::new(req)).await?.into_inner();
        Ok(res.effective)
    }

    pub async fn submit_evaluation(&mut self, negotiation_id: &str, report: EvaluationReport) -> Result<bool> {
        let req = SubmitEvaluationRequest { negotiation_id: negotiation_id.to_string(), report: Some(report) };
        let res = self.client.submit_evaluation(tonic::Request::new(req)).await?.into_inner();
        Ok(res.accepted)
    }

    pub async fn hitl_action(&mut self, negotiation_id: &str, action: &str, rationale: &str) -> Result<bool> {
        let req = HitlActionRequest { negotiation_id: negotiation_id.to_string(), action: action.to_string(), rationale: rationale.to_string() };
        let res = self.client.hitl_action(tonic::Request::new(req)).await?.into_inner();
        Ok(res.ok)
    }
}

