use sw4rm_sdk::secrets::{types::*, backend::SecretsBackend, resolver::Resolver, backends::file::FileBackend, factory::{select_backend, BackendMode}};

#[test]
fn precedence_resolver_cli_then_env_then_scoped_then_global() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("secrets.json");
    let fb = FileBackend::new(Some(path)).expect("file backend");

    let key = SecretKey::new("provider.example.api_key");
    let scoped = Scope::new("dev");
    let global = Scope::global();

    fb.set(&global, &key, &SecretValue::new("GLOB").unwrap()).unwrap();
    fb.set(&scoped, &key, &SecretValue::new("SCOP").unwrap()).unwrap();

    // explicit CLI wins
    let r = Resolver::new(&fb);
    let (v, src) = r.resolve(&key, &scoped, Some("CLI"), None).unwrap();
    assert_eq!(v, "CLI");
    assert_eq!(src, SecretSource::Cli);

    // env wins over stored
    std::env::set_var("EX_API_KEY", "ENV");
    let (v, src) = r.resolve(&key, &scoped, None, Some("EX_API_KEY")).unwrap();
    assert_eq!(v, "ENV");
    assert_eq!(src, SecretSource::Env);
    std::env::remove_var("EX_API_KEY");

    // scoped over global
    let (v, src) = r.resolve(&key, &scoped, None, None).unwrap();
    assert_eq!(v, "SCOP");
    assert_eq!(src, SecretSource::Scoped);

    // global when scope missing
    let (v, src) = r.resolve(&key, &Scope::new("missing"), None, None).unwrap();
    assert_eq!(v, "GLOB");
    assert_eq!(src, SecretSource::Global);
}

#[test]
#[cfg(unix)]
fn file_backend_enforces_0600() {
    use std::os::unix::fs::PermissionsExt;
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("secrets.json");
    let fb = FileBackend::new(Some(path.clone())).expect("file backend");
    let meta = std::fs::metadata(&path).unwrap();
    let mode = meta.permissions().mode() & 0o777;
    assert_eq!(mode, 0o600);
    // write one secret and ensure perms remain strict
    let key = SecretKey::new("provider.example.api_key");
    fb.set(&Scope::global(), &key, &SecretValue::new("abc").unwrap()).unwrap();
    let mode2 = std::fs::metadata(&path).unwrap().permissions().mode() & 0o777;
    assert_eq!(mode2, 0o600);
}

#[test]
fn backend_selection_prefers_file_in_ci() {
    std::env::set_var("CI", "1");
    let (_b, name) = select_backend(Some(BackendMode::Auto)).expect("select backend");
    assert_eq!(name, "file");
    std::env::remove_var("CI");
}

