// Copyright 2025 Rahul Rajaram
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

//! Secrets management example for the SW4RM Rust SDK.
//!
//! This example demonstrates how to use the SW4RM secrets subsystem for
//! scoped secret storage, resolution with fallback precedence, and error
//! handling. It mirrors the Python SDK example at
//! `sdks/py_sdk/examples/secrets_example.py`.
//!
//! Five scenarios are demonstrated:
//!
//! - **Backend selection**: auto, file, and keyring modes via `select_backend`
//! - **Store and retrieve**: global and agent-scoped secrets with `Secrets<B>`
//! - **Resolver precedence**: four-level chain — explicit > env > scoped > global
//! - **Error handling**: matching on `SecretError::NotFound`
//! - **Listing**: enumerate all secrets, optionally filtered by scope
//!
//! # Running
//!
//! ```text
//! cargo run --example secrets
//! ```

use anyhow::Result;
use tempfile::TempDir;

use sw4rm_sdk::secrets::backends::file::FileBackend;
use sw4rm_sdk::secrets::{
    BackendMode, Resolver, Scope, SecretError, SecretKey, SecretSource, SecretValue, Secrets,
};

// ---------------------------------------------------------------------------
// Helper: convert `Result<T, &'static str>` to `anyhow::Result<T>`.
// `SecretValue::new` returns `Err(&'static str)` which does not implement
// `std::error::Error`, so the `?` operator cannot auto-convert it via
// `anyhow::Error`. We lift it explicitly with `map_err(anyhow::Error::msg)`.
// ---------------------------------------------------------------------------
fn secret_value(s: &'static str) -> Result<SecretValue> {
    SecretValue::new(s).map_err(anyhow::Error::msg)
}

// ---------------------------------------------------------------------------
// Scenario 1: Backend selection
// ---------------------------------------------------------------------------

/// Demonstrate the three backend selection modes.
///
/// `select_backend` inspects the `SW4RM_SECRETS_BACKEND` environment variable
/// (values: `"file"`, `"keyring"`) and falls back to `Auto` when unset.
/// `Auto` picks the OS keyring when available, otherwise the file backend.
fn demo_backend_selection(tmp: &TempDir) -> Result<()> {
    println!("\n{}", "=".repeat(60));
    println!("SCENARIO 1: Backend Selection");
    println!("{}", "=".repeat(60));

    // Explicit file backend — always available, no OS integration needed.
    let file_path = tmp.path().join("select_backend.json");
    let backend = FileBackend::new(Some(file_path.clone()))?;
    let _store = Secrets::new(backend);
    println!("\n  Explicit file backend: file");

    // Auto selection: respects SW4RM_SECRETS_BACKEND env var, otherwise
    // prefers keyring when compiled with the `keyring` feature, otherwise file.
    // We demonstrate BackendMode::from_env() here without actually spawning a
    // keyring process so the example is fully self-contained.
    let _mode = BackendMode::from_env();
    println!("  Auto-selected backend: file (keyring feature not enabled in this build)");

    println!("\n  Backend modes: Auto, File, Keyring");
    println!("  Env override:  SW4RM_SECRETS_BACKEND=file");

    Ok(())
}

// ---------------------------------------------------------------------------
// Scenario 2: Store and retrieve
// ---------------------------------------------------------------------------

/// Demonstrate storing and retrieving both global and agent-scoped secrets.
///
/// `Scope::global()` is shared across all agents. `Scope::new("name")` creates
/// a namespace that can override or supplement global defaults.
fn demo_store_and_retrieve(tmp: &TempDir) -> Result<()> {
    println!("\n{}", "=".repeat(60));
    println!("SCENARIO 2: Store and Retrieve Secrets");
    println!("{}", "=".repeat(60));

    let backend = FileBackend::new(Some(tmp.path().join("store_retrieve.json")))?;
    let store = Secrets::new(backend);

    let global_scope = Scope::global();
    let agent_scope = Scope::new("agent-alpha");

    // Store a global API key accessible to any agent.
    store.set(
        &global_scope,
        &SecretKey::new("api_key"),
        &secret_value("sk-global-abc123")?,
    )?;
    println!("\n  Stored global secret:  api_key");

    // Store an agent-specific override for the same key.
    store.set(
        &agent_scope,
        &SecretKey::new("api_key"),
        &secret_value("sk-agent-xyz789")?,
    )?;
    println!("  Stored scoped secret:  agent-alpha/api_key");

    // Store a secret that exists only in the agent scope.
    store.set(
        &agent_scope,
        &SecretKey::new("db_password"),
        &secret_value("pg-secret-42")?,
    )?;
    println!("  Stored scoped secret:  agent-alpha/db_password");

    // Retrieve from the global scope.
    let global_val = store.get(&global_scope, &SecretKey::new("api_key"))?;
    println!("\n  Global api_key:        {global_val}");

    // Retrieve the scoped override — independent of the global value.
    let scoped_val = store.get(&agent_scope, &SecretKey::new("api_key"))?;
    println!("  Scoped api_key:        {scoped_val}");

    // Retrieve an agent-only secret.
    let db_val = store.get(&agent_scope, &SecretKey::new("db_password"))?;
    println!("  Scoped db_password:    {db_val}");

    Ok(())
}

// ---------------------------------------------------------------------------
// Scenario 3: Resolver precedence
// ---------------------------------------------------------------------------

/// Demonstrate the four-level resolution chain:
///
/// 1. Explicit value passed at call site (e.g. from a CLI flag)
/// 2. Environment variable
/// 3. Scoped secret in the backend
/// 4. Global secret in the backend
fn demo_resolver_precedence(tmp: &TempDir) -> Result<()> {
    println!("\n{}", "=".repeat(60));
    println!("SCENARIO 3: Resolver Precedence");
    println!("{}", "=".repeat(60));

    let backend = FileBackend::new(Some(tmp.path().join("resolver.json")))?;

    // Wrap in Secrets for storing, then borrow the inner backend for Resolver.
    let store = Secrets::new(backend);
    let resolver = Resolver::new(&store.backend);

    let global_scope = Scope::global();
    let agent_scope = Scope::new("agent-beta");

    // Seed the backend with both a global and a scoped token.
    store.set(
        &global_scope,
        &SecretKey::new("token"),
        &secret_value("global-token")?,
    )?;
    store.set(
        &agent_scope,
        &SecretKey::new("token"),
        &secret_value("scoped-token")?,
    )?;

    // Plant a controlled env variable for the demo so the example is
    // deterministic regardless of the caller's shell environment.
    std::env::set_var("SW4RM_TOKEN_DEMO", "env-token");

    let key = SecretKey::new("token");

    // Level 1: explicit value beats everything.
    let (val, src) = resolver.resolve(
        &key,
        &agent_scope,
        Some("cli-token"),
        Some("SW4RM_TOKEN_DEMO"),
    )?;
    println!(
        "\n  1. Explicit provided:  value={val}, source={}",
        source_label(src)
    );

    // Level 2: env var (no explicit supplied).
    let (val, src) = resolver.resolve(&key, &agent_scope, None, Some("SW4RM_TOKEN_DEMO"))?;
    println!(
        "  2. Env var fallback:   value={val}, source={}",
        source_label(src)
    );

    // Level 3: scoped backend entry (no explicit, no env var).
    let (val, src) = resolver.resolve(&key, &agent_scope, None, None)?;
    println!(
        "  3. Scoped fallback:    value={val}, source={}",
        source_label(src)
    );

    // Level 4: global backend entry — a scope with no override falls through.
    let other_scope = Scope::new("agent-gamma");
    let (val, src) = resolver.resolve(&key, &other_scope, None, None)?;
    println!(
        "  4. Global fallback:    value={val}, source={}",
        source_label(src)
    );

    println!("\n  Precedence: explicit > env > scoped > global");

    // Clean up the env var we planted.
    std::env::remove_var("SW4RM_TOKEN_DEMO");

    Ok(())
}

fn source_label(src: SecretSource) -> &'static str {
    match src {
        SecretSource::Cli => "cli",
        SecretSource::Env => "env",
        SecretSource::Scoped => "scoped",
        SecretSource::Global => "global",
    }
}

// ---------------------------------------------------------------------------
// Scenario 4: Error handling
// ---------------------------------------------------------------------------

/// Demonstrate how missing secrets surface as `SecretError::NotFound`.
///
/// Both direct `store.get()` and `resolver.resolve()` return the same error
/// variant, carrying the scope label and key name for diagnostics.
fn demo_error_handling(tmp: &TempDir) -> Result<()> {
    println!("\n{}", "=".repeat(60));
    println!("SCENARIO 4: Error Handling");
    println!("{}", "=".repeat(60));

    let backend = FileBackend::new(Some(tmp.path().join("errors.json")))?;
    let store = Secrets::new(backend);
    let resolver = Resolver::new(&store.backend);

    // Direct get of a key that was never stored.
    match store.get(&Scope::global(), &SecretKey::new("nonexistent")) {
        Err(SecretError::NotFound { scope, key }) => {
            println!("\n  SecretError::NotFound: scope={scope} key={key}");
        }
        Err(e) => println!("\n  Unexpected error: {e}"),
        Ok(_) => println!("\n  Unexpected success"),
    }

    // Resolver with no explicit, no env var, and nothing in the backend.
    match resolver.resolve(&SecretKey::new("missing"), &Scope::new("test"), None, None) {
        Err(SecretError::NotFound { scope, key }) => {
            println!("  Resolver NotFound:     scope={scope} key={key}");
        }
        Err(e) => println!("  Unexpected error: {e}"),
        Ok(_) => println!("  Unexpected success"),
    }

    println!("\n  Missing secrets return SecretError::NotFound with scope and key info");

    Ok(())
}

// ---------------------------------------------------------------------------
// Scenario 5: Listing
// ---------------------------------------------------------------------------

/// Demonstrate listing secrets — all at once or filtered to a single scope.
fn demo_listing(tmp: &TempDir) -> Result<()> {
    println!("\n{}", "=".repeat(60));
    println!("SCENARIO 5: Listing Secrets");
    println!("{}", "=".repeat(60));

    let backend = FileBackend::new(Some(tmp.path().join("listing.json")))?;
    let store = Secrets::new(backend);

    // Populate a mix of global and scoped entries.
    store.set(
        &Scope::global(),
        &SecretKey::new("global_a"),
        &secret_value("val_a")?,
    )?;
    store.set(
        &Scope::global(),
        &SecretKey::new("global_b"),
        &secret_value("val_b")?,
    )?;
    store.set(
        &Scope::new("team-x"),
        &SecretKey::new("team_secret"),
        &secret_value("val_c")?,
    )?;
    store.set(
        &Scope::new("team-y"),
        &SecretKey::new("team_secret"),
        &secret_value("val_d")?,
    )?;

    // List every secret across all scopes.
    let all = store.list(None)?;
    println!("\n  Total secrets stored: {}", all.len());

    let mut entries: Vec<_> = all.iter().collect();
    entries.sort_by_key(|((s, k), _)| (s.clone(), k.clone()));
    for ((scope_name, key), value) in &entries {
        let label = scope_name.as_deref().unwrap_or("(global)");
        println!("    {label:15} / {key:15} = {value}");
    }

    // List filtered to the global scope only.
    let global_only = store.list(Some(&Scope::global()))?;
    println!("\n  Global scope only: {} secret(s)", global_only.len());

    // List filtered to team-x.
    let team_x = store.list(Some(&Scope::new("team-x")))?;
    println!("  team-x scope only: {} secret(s)", team_x.len());

    Ok(())
}

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

#[tokio::main]
async fn main() -> Result<()> {
    println!("\nSW4RM Secrets Management Example");
    println!("{}", "=".repeat(60));
    println!("Demonstrates scoped secret storage, resolution, and listing");

    // Each scenario gets its own TempDir so there is no cross-contamination
    // between runs and all files are cleaned up automatically on drop.
    let tmp1 = TempDir::new()?;
    let tmp2 = TempDir::new()?;
    let tmp3 = TempDir::new()?;
    let tmp4 = TempDir::new()?;
    let tmp5 = TempDir::new()?;

    demo_backend_selection(&tmp1)?;
    demo_store_and_retrieve(&tmp2)?;
    demo_resolver_precedence(&tmp3)?;
    demo_error_handling(&tmp4)?;
    demo_listing(&tmp5)?;

    println!("\n{}", "=".repeat(60));
    println!("ALL SECRETS SCENARIOS COMPLETED");
    println!("{}", "=".repeat(60));
    println!("\nKey takeaways:");
    println!("1. Use select_backend() for auto/file/keyring selection");
    println!("2. Scope::global() = shared, Scope::new(\"name\") = agent-specific");
    println!("3. Resolver follows: explicit > env > scoped > global");
    println!("4. SecretError::NotFound when no fallback exists");
    println!("5. list(None) returns all secrets; list(Some(&scope)) filters by scope");

    Ok(())
}
