use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum SecretSource {
    Cli,
    Env,
    Scoped,
    Global,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Hash)]
pub struct Scope(pub Option<String>);

impl Scope {
    pub fn global() -> Self { Self(None) }
    pub fn new(name: impl Into<String>) -> Self { Self(Some(name.into())) }
    pub fn is_global(&self) -> bool { self.0.is_none() }
    pub fn label(&self) -> &str { self.0.as_deref().unwrap_or("global") }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Hash)]
pub struct SecretKey(pub String);

impl SecretKey {
    pub fn new(s: impl Into<String>) -> Self { Self(s.into()) }
    pub fn validate(&self) -> Result<(), &'static str> {
        if self.0.is_empty() { return Err("secret key cannot be empty"); }
        if self.0.split('.').any(|p| p.trim().is_empty()) {
            return Err("secret key must be dotted identifiers without empty segments");
        }
        Ok(())
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct SecretValue(pub String);

impl SecretValue {
    pub const MAX_LEN: usize = 8 * 1024;
    pub fn new(s: impl Into<String>) -> Result<Self, &'static str> {
        let s = s.into();
        if s.len() > Self::MAX_LEN { return Err("secret value exceeds maximum length (8KB)"); }
        Ok(Self(s))
    }
}
