# Secrets Architecture (Bee CLI & SDKs)

This document describes the Secrets subsystem: interfaces, backends, Bee CLI, and resolution semantics across SDKs (Rust, Python, JS).

## Scope and Keys
- Scope: `global` or a hive name. Global scope applies to all hives; hive scope overrides or augments global.
- Key schema: dotted identifiers, e.g. `provider.anthropic.api_key`. Empty segments are rejected.

## Precedence
When resolving a secret value, the system follows this order:
1. Explicit value (e.g., CLI flag or direct parameter)
2. Environment variable (if provided via `--env-var NAME`/equivalent)
3. Scoped secret (hive-specific)
4. Global secret

The resolver returns both the value and the source (`cli | env | scoped | global`). When an environment variable shadows a stored secret, a warning is emitted unless suppressed.

## Backends

Two storage backends are supported:
- Keyring: Uses OS credential manager (Python: `keyring`, JS: `keytar`, Rust: `keyring` feature). Listing is intentionally not supported for safety.
- File: JSON file stored at user config dir (`~/.config/sw4rm/secrets.json` on POSIX, `%APPDATA%/sw4rm/secrets.json` on Windows).

Security notes for file backend:
- POSIX file mode is tightened to `0600` (owner read/write). Parent directory is set to `0700` best-effort.
- Atomic writes are used (write temp file, fsync, replace).

## Backend Selection

Selection is controllable via flag or environment:
- Env: `SW4RM_SECRETS_BACKEND=auto|file|keyring`
- Auto mode prefers file in CI (`CI=1`), otherwise tries keyring then falls back to file.
- Bee CLI flag: `--backend auto|file|keyring`
- Rust feature: keyring support is behind the `keyring` feature in `sw4rm-sdk`.

## Bee CLI

Commands are provided via the Rust `bee` binary:
- Set: `bee secret set --key <key> [--value <val> | --stdin] [--scope <hive> | --global] [--backend auto|file|keyring]`
- Get: `bee secret get --key <key> [--env-var <NAME>] [--no-warn] [--scope <hive> | --global] [--backend …]`
- List: `bee secret list [--all-scopes | --scope <hive> | --global] [--include-values] [--backend …]`

Notes:
- `--stdin` reads the secret value from standard input.
- `--include-values` does not print raw values in text mode; they are masked as `***`. JSON outputs can include values when needed (future extension).

## SDK APIs

### Rust (`sw4rm-sdk`)
- Types: `Scope`, `SecretKey`, `SecretValue`, `SecretSource`.
- Resolver: `Resolver::resolve(&key, &scope, explicit, env_var)` -> `(String, SecretSource)`.
- Backend selection: `select_backend(Some(BackendMode::Auto))` or from env.

Example:
```rust
use sw4rm_sdk::secrets::{select_backend, BackendMode, Resolver, Scope, SecretKey};
let (backend, _) = select_backend(Some(BackendMode::Auto))?;
let resolver = Resolver::new(backend.as_ref());
let (value, source) = resolver.resolve(&SecretKey::new("provider.anthropic.api_key"), &Scope::new("my-hive"), None, Some("ANTHROPIC_API_KEY"))?;
```

### Python (SDK only)
- Types: `Scope`, `SecretKey`, `SecretValue`, `SecretSource`.
- Resolver: `Resolver(backend).resolve(key, scope, explicit=None, env_var=None)`.
- Selection: `select_backend(mode=None)` reads `SW4RM_SECRETS_BACKEND`.

### JS/TS
- Types: `Scope`, `SecretKey`, `SecretValue`, `SecretSource`.
- Resolver: `await new Resolver(backend).resolve(key, scope, { explicit, envVar })`.
- Selection: `await selectBackend(mode?)` reads `SW4RM_SECRETS_BACKEND`.

## Limits and Validation
- Max secret size: 8KB (configurable in code). Larger values are rejected.
- Keys must be dotted identifiers with no empty segments.
- Values are never logged; audit logs should capture only scope/key and outcome (future work).

## CI and Headless Environments
- Auto mode selects file backend when `CI` env var is set.
- Use `--backend file` or `SW4RM_SECRETS_BACKEND=file` to avoid keychain prompts on headless servers.

## Non-Goals (current milestone)
- No cloud secret manager integrations; no automatic rotation.
- Keyring backends do not support listing.

## Roadmap
- Audit logging without values.
- Optional import/export (`bee secret import`) for scoped archives.
- Telemetry counters for set/get/list and backend selection (no values).
- Provider helpers: convenience methods to fetch `provider.*.api_key` by scope across SDKs.
