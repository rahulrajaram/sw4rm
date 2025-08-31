#[cfg(feature = "keyring")]
use std::collections::HashMap;

#[cfg(feature = "keyring")]
use crate::secrets::backend::SecretsBackend;
#[cfg(feature = "keyring")]
use crate::secrets::errors::{Result, SecretError};
#[cfg(feature = "keyring")]
use crate::secrets::types::{Scope, SecretKey, SecretValue};

#[cfg(feature = "keyring")]
#[derive(Debug, Clone)]
pub struct KeyringBackend {
    service_prefix: String,
}

#[cfg(feature = "keyring")]
impl KeyringBackend {
    pub fn new(service_prefix: impl Into<String>) -> Self {
        Self {
            service_prefix: service_prefix.into(),
        }
    }
    fn service(&self, scope: &Scope) -> String {
        format!("{}:{}", self.service_prefix, scope.label())
    }
}

#[cfg(feature = "keyring")]
impl SecretsBackend for KeyringBackend {
    fn set(&self, scope: &Scope, key: &SecretKey, value: &SecretValue) -> Result<()> {
        let service = self.service(scope);
        keyring::Entry::new(&service, &key.0)
            .and_then(|e| e.set_password(&value.0))
            .map_err(|e| SecretError::Backend(e.to_string()))
    }

    fn get(&self, scope: &Scope, key: &SecretKey) -> Result<String> {
        let service = self.service(scope);
        match keyring::Entry::new(&service, &key.0).and_then(|e| e.get_password()) {
            Ok(v) => Ok(v),
            Err(_) => Err(SecretError::NotFound {
                scope: scope.label().to_string(),
                key: key.0.clone(),
            }),
        }
    }

    fn list(&self, _scope: Option<&Scope>) -> Result<HashMap<(Option<String>, String), String>> {
        // Keyring crate does not support listing. Return empty.
        Ok(HashMap::new())
    }
}
