use std::collections::HashMap;
use std::fs::{self, OpenOptions};
use std::io::Write;
use std::path::PathBuf;

use serde_json::Value as Json;

use crate::secrets::backend::SecretsBackend;
use crate::secrets::errors::{Result, SecretError};
use crate::secrets::types::{Scope, SecretKey, SecretValue};

#[derive(Debug, Clone)]
pub struct FileBackend {
    path: PathBuf,
}

impl FileBackend {
    pub fn new(path: Option<PathBuf>) -> Result<Self> {
        let path = path.unwrap_or_else(default_path);
        if let Some(dir) = path.parent() {
            fs::create_dir_all(dir).map_err(|e| SecretError::Permission(e.to_string()))?;
        }
        if !path.exists() {
            write_atomic(&path, &Json::Object(Default::default()))?;
            enforce_file_perms(&path)?;
        } else {
            enforce_file_perms(&path)?;
        }
        Ok(Self { path })
    }
}

fn default_path() -> PathBuf {
    let base = directories::BaseDirs::new()
        .map(|b| b.config_dir().to_path_buf())
        .unwrap_or_else(dirs_fallback);
    base.join("sw4rm").join("secrets.json")
}

// Fallback for when `directories::BaseDirs::new()` returns None.
// Attempts common config locations before defaulting to current directory.
fn dirs_fallback() -> PathBuf {
    if let Some(xdg) = std::env::var_os("XDG_CONFIG_HOME") {
        return PathBuf::from(xdg);
    }
    if let Some(home) = std::env::var_os("HOME") {
        return PathBuf::from(home).join(".config");
    }
    // As a last resort, use the current working directory
    std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."))
}

#[cfg(unix)]
fn enforce_file_perms(path: &PathBuf) -> Result<()> {
    use std::os::unix::fs::PermissionsExt;
    let meta = fs::metadata(path).map_err(|e| SecretError::Permission(e.to_string()))?;
    let mut perm = meta.permissions();
    let mode = perm.mode();
    if (mode & 0o077) != 0 {
        // any group/other perms
        perm.set_mode(0o600);
        fs::set_permissions(path, perm).map_err(|e| SecretError::Permission(e.to_string()))?;
    }
    Ok(())
}

#[cfg(not(unix))]
fn enforce_file_perms(_path: &PathBuf) -> Result<()> {
    Ok(())
}

fn write_atomic(path: &PathBuf, data: &Json) -> Result<()> {
    let tmp = path.with_extension("tmp");
    {
        let mut f = OpenOptions::new()
            .create(true)
            .write(true)
            .truncate(true)
            .open(&tmp)
            .map_err(|e| SecretError::Permission(e.to_string()))?;
        let s =
            serde_json::to_string_pretty(data).map_err(|e| SecretError::Backend(e.to_string()))?;
        f.write_all(s.as_bytes())
            .map_err(|e| SecretError::Backend(e.to_string()))?;
        f.flush().map_err(|e| SecretError::Backend(e.to_string()))?;
    }
    fs::rename(&tmp, path).map_err(|e| SecretError::Backend(e.to_string()))?;
    enforce_file_perms(path)?;
    Ok(())
}

impl SecretsBackend for FileBackend {
    fn set(&self, scope: &Scope, key: &SecretKey, value: &SecretValue) -> Result<()> {
        let mut data: Json = fs::read_to_string(&self.path)
            .ok()
            .and_then(|s| serde_json::from_str(&s).ok())
            .unwrap_or_else(|| Json::Object(Default::default()));
        let bucket = data
            .as_object_mut()
            .unwrap()
            .entry(scope.label().to_string())
            .or_insert(Json::Object(Default::default()));
        let bucket = bucket.as_object_mut().unwrap();
        bucket.insert(key.0.clone(), Json::String(value.0.clone()));
        write_atomic(&self.path, &data)
    }

    fn get(&self, scope: &Scope, key: &SecretKey) -> Result<String> {
        let data: Json = fs::read_to_string(&self.path)
            .ok()
            .and_then(|s| serde_json::from_str(&s).ok())
            .unwrap_or_else(|| Json::Object(Default::default()));
        let v = data
            .get(scope.label())
            .and_then(|b| b.get(&key.0))
            .and_then(|v| v.as_str())
            .map(|s| s.to_string());
        v.ok_or_else(|| SecretError::NotFound {
            scope: scope.label().to_string(),
            key: key.0.clone(),
        })
    }

    fn list(&self, scope: Option<&Scope>) -> Result<HashMap<(Option<String>, String), String>> {
        let data: Json = fs::read_to_string(&self.path)
            .ok()
            .and_then(|s| serde_json::from_str(&s).ok())
            .unwrap_or_else(|| Json::Object(Default::default()));
        let mut out = HashMap::new();
        if let Some(scope) = scope {
            if let Some(bucket) = data.get(scope.label()).and_then(|b| b.as_object()) {
                for (k, v) in bucket.iter() {
                    if let Some(s) = v.as_str() {
                        out.insert((scope.0.clone(), k.clone()), s.to_string());
                    }
                }
            }
            return Ok(out);
        }
        if let Some(root) = data.as_object() {
            for (scope_name, bucket) in root.iter() {
                if let Some(bucket) = bucket.as_object() {
                    for (k, v) in bucket.iter() {
                        if let Some(s) = v.as_str() {
                            let sname = if scope_name == "global" {
                                None
                            } else {
                                Some(scope_name.clone())
                            };
                            out.insert((sname, k.clone()), s.to_string());
                        }
                    }
                }
            }
        }
        Ok(out)
    }
}
