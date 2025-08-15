use crate::secrets::errors::{Result, SecretError};
use crate::secrets::types::{Scope, SecretKey, SecretSource};
use crate::secrets::backend::SecretsBackend;

pub struct Resolver<'a, B: SecretsBackend + ?Sized> { backend: &'a B }

impl<'a, B: SecretsBackend + ?Sized> Resolver<'a, B> {
    pub fn new(backend: &'a B) -> Self { Self { backend } }

    pub fn resolve(&self, key: &SecretKey, scope: &Scope, explicit: Option<&str>, env_var: Option<&str>) -> Result<(String, SecretSource)> {
        if let Some(v) = explicit { return Ok((v.to_string(), SecretSource::Cli)); }
        if let Some(var) = env_var { if let Ok(v) = std::env::var(var) { if !v.is_empty() { return Ok((v, SecretSource::Env)); } } }
        if let Ok(v) = self.backend.get(scope, key) { return Ok((v, if scope.is_global() { SecretSource::Global } else { SecretSource::Scoped })); }
        if !scope.is_global() {
            if let Ok(v) = self.backend.get(&Scope::global(), key) { return Ok((v, SecretSource::Global)); }
        }
        Err(SecretError::NotFound { scope: scope.label().to_string(), key: key.0.clone() })
    }
}
