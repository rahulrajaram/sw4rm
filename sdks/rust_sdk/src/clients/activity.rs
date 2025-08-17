use crate::proto::sw4rm::activity::activity_service_client::ActivityServiceClient;
use crate::proto::sw4rm::activity::{AppendArtifactRequest, ListArtifactsRequest, Artifact};
use crate::{Error, Result};
use tonic::transport::{Channel, Endpoint};

#[derive(Debug, Clone)]
pub struct ActivityClient {
    client: ActivityServiceClient<Channel>,
}

impl ActivityClient {
    pub async fn new(endpoint: &str) -> Result<Self> {
        let channel = Endpoint::from_shared(endpoint.to_string())
            .map_err(|e| Error::Config(format!("Invalid endpoint: {}", e)))?
            .connect()
            .await?;
        Ok(Self { client: ActivityServiceClient::new(channel) })
    }

    pub async fn append_artifact(&mut self, artifact: Artifact) -> Result<bool> {
        let req = AppendArtifactRequest { artifact: Some(artifact) };
        let res = self.client.append_artifact(tonic::Request::new(req)).await?.into_inner();
        Ok(res.ok)
    }

    pub async fn list_artifacts(&mut self, negotiation_id: &str, kind: Option<&str>) -> Result<Vec<Artifact>> {
        let req = ListArtifactsRequest { negotiation_id: negotiation_id.to_string(), kind: kind.unwrap_or("").to_string() };
        let res = self.client.list_artifacts(tonic::Request::new(req)).await?.into_inner();
        Ok(res.items)
    }
}

