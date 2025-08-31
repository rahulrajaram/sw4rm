use crate::secrets::backend::SecretsBackend;
use crate::secrets::backends::file::FileBackend;
use crate::secrets::errors::Result;
#[cfg(not(feature = "keyring"))]
use crate::secrets::errors::SecretError;

#[derive(Debug, Clone, Copy)]
pub enum BackendMode {
    Auto,
    File,
    Keyring,
}

impl BackendMode {
    pub fn from_env() -> Self {
        match std::env::var("SW4RM_SECRETS_BACKEND").ok().as_deref() {
            Some("file") => BackendMode::File,
            Some("keyring") => BackendMode::Keyring,
            _ => BackendMode::Auto,
        }
    }
}

pub fn select_backend(
    mode: Option<BackendMode>,
) -> Result<(Box<dyn SecretsBackend>, &'static str)> {
    let mode = mode.unwrap_or_else(BackendMode::from_env);
    match mode {
        BackendMode::File => Ok((Box::new(FileBackend::new(None)?), "file")),
        BackendMode::Keyring => {
            #[cfg(feature = "keyring")]
            {
                use crate::secrets::backends::keyring::KeyringBackend;
                Ok((Box::new(KeyringBackend::new("sw4rm")), "keyring"))
            }
            #[cfg(not(feature = "keyring"))]
            {
                Err(SecretError::Backend("keyring feature not enabled; recompile with \"keyring\" feature or use file backend".into()))
            }
        }
        BackendMode::Auto => {
            if std::env::var("CI").is_ok() {
                return Ok((Box::new(FileBackend::new(None)?), "file"));
            }
            #[cfg(feature = "keyring")]
            {
                use crate::secrets::backends::keyring::KeyringBackend;
                Ok((Box::new(KeyringBackend::new("sw4rm")), "keyring"))
            }
            #[cfg(not(feature = "keyring"))]
            {
                Ok((Box::new(FileBackend::new(None)?), "file"))
            }
        }
    }
}
