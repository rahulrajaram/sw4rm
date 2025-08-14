use std::collections::HashMap;

use super::errors::Result;
use super::types::{Scope, SecretKey, SecretValue};

pub trait SecretsBackend: Send + Sync {
    fn set(&self, scope: &Scope, key: &SecretKey, value: &SecretValue) -> Result<()>;
    fn get(&self, scope: &Scope, key: &SecretKey) -> Result<String>;
    fn list(&self, scope: Option<&Scope>) -> Result<HashMap<(Option<String>, String), String>>;
}

pub struct Secrets<B: SecretsBackend> { pub backend: B }

impl<B: SecretsBackend> Secrets<B> {
    pub fn new(backend: B) -> Self { Self { backend } }
    pub fn set(&self, scope: &Scope, key: &SecretKey, value: &SecretValue) -> Result<()> { self.backend.set(scope, key, value) }
    pub fn get(&self, scope: &Scope, key: &SecretKey) -> Result<String> { self.backend.get(scope, key) }
    pub fn list(&self, scope: Option<&Scope>) -> Result<HashMap<(Option<String>, String), String>> { self.backend.list(scope) }
}
