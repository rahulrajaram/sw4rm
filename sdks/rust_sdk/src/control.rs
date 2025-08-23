use serde::{Deserialize, Serialize};

/// Content types for CONTROL-only orchestration
pub const CT_SCHEDULER_COMMAND_V1: &str = "application/vnd.sw4rm.scheduler.command+json;v=1";
pub const CT_AGENT_REPORT_V1: &str = "application/vnd.sw4rm.agent.report+json;v=1";

/// Stages supported by scheduler CONTROL commands
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum SchedulerStage {
    Prompt,
    Plan,
    Run,
}

/// Scheduler CONTROL command (v1)
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct SchedulerCommandV1 {
    pub stage: SchedulerStage,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub input: Option<serde_json::Value>,
}

impl SchedulerCommandV1 {
    pub fn new(stage: SchedulerStage) -> Self {
        Self { stage, input: None }
    }

    pub fn with_input(mut self, input: serde_json::Value) -> Self {
        self.input = Some(input);
        self
    }

    pub fn to_bytes(&self) -> Result<Vec<u8>, serde_json::Error> {
        serde_json::to_vec(self)
    }
}

/// Agent report with base64 files (v1)
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct AgentReportV1 {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub agent_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub stage: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub success: Option<bool>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub files: Option<Vec<AgentReportFileV1>>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub logs: Option<Vec<String>>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct AgentReportFileV1 {
    pub path: String,
    pub b64: String,
}

impl AgentReportV1 {
    /// Normalize file paths to POSIX style (forward slashes) and collapse redundancies
    pub fn normalize_paths(&mut self) {
        if let Some(files) = &mut self.files {
            for f in files.iter_mut() {
                // Replace backslashes and collapse duplicate slashes
                let replaced = f.path.replace('\\', "/");
                let normalized = normalize_posix_path(&replaced);
                f.path = normalized;
            }
        }
    }
}

fn normalize_posix_path(p: &str) -> String {
    let mut out: Vec<&str> = Vec::new();
    for part in p.split('/') {
        match part {
            "" | "." => {}
            ".." => {
                out.pop();
            }
            other => out.push(other),
        }
    }
    out.join("/")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn scheduler_command_roundtrip() {
        let cmd = SchedulerCommandV1::new(SchedulerStage::Run)
            .with_input(serde_json::json!({"foo":"bar","n":1}));
        let bytes = cmd.to_bytes().unwrap();
        let decoded: SchedulerCommandV1 = serde_json::from_slice(&bytes).unwrap();
        assert_eq!(decoded.stage, SchedulerStage::Run);
        assert_eq!(decoded.input.unwrap()["foo"], "bar");
    }

    #[test]
    fn normalize_agent_report_paths() {
        let mut report = AgentReportV1 {
            agent_id: Some("a1".into()),
            stage: Some("generate".into()),
            success: Some(true),
            files: Some(vec![
                AgentReportFileV1 { path: "..\\generated_app\\..//src/../src//main.js".into(), b64: "".into() },
                AgentReportFileV1 { path: "./frontend/./src//App.tsx".into(), b64: "".into() },
            ]),
            logs: None,
            error: None,
        };
        report.normalize_paths();
        let files = report.files.unwrap();
        assert_eq!(files[0].path, "src/main.js");
        assert_eq!(files[1].path, "frontend/src/App.tsx");
    }
}
