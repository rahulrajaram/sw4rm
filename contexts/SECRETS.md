# Secrets Milestone — Progress Summary

This document tracks progress for the Secrets Management milestone (scoped secrets, backends, CLI) tied to branch `secrets-cli-scoped-env`.

## Status Overview
- Core interfaces and types implemented across Python, Rust, and JS SDKs.
- File and keyring backends implemented (keyring optional/enabled by feature where applicable).
- Resolver implements precedence: explicit > env > scoped > global.
- Bee CLI provides `secret set|get|list` with scoping and backend selection.
- Backend selection via flag and `SW4RM_SECRETS_BACKEND`; auto prefers file in CI.
- File backend enforces 0600 (POSIX), atomic writes, and safe parent dir perms.

## Artifacts
- Python: `sdks/py_sdk/sw4rm/secrets/` (types, errors, backend protocol, resolver, backends, factory)
- Rust: `sdks/rust_sdk/src/secrets/` (types.rs, errors.rs, backend.rs, resolver.rs, backends/, factory.rs)
- JS: `sdks/js_sdk/src/secrets/` (types.ts, errors.ts, backend.ts, resolver.ts, backends/, factory.ts)
- Bee CLI: `bee/src/main.rs` new `Secret` subcommands.
- Docs: `documentation/architecture/SECRETS.md` and mkdocs nav entry.

## Backend Selection
- Flag: `--backend auto|file|keyring` (Bee CLI).
- Env: `SW4RM_SECRETS_BACKEND=auto|file|keyring` across SDKs.
- CI behavior: `CI=1` selects file in auto mode.
- Rust keyring: behind Cargo feature `keyring` on `sw4rm-sdk`.

## Checklist (updated)
- [x] Core API: Define `Secrets` trait/traits, `Scope`, `SecretKey`, `SecretValue`, and typed errors.
- [x] Backends: Implement OS keyring backend; add file backend fallback with mode 0600.
- [x] Scoping: Establish scope model (global | hive) and key schema `provider.<name>.<field>` with validation.
- [x] Resolution: Implement precedence resolver (CLI > env > scoped > global) returning value and source.
- [x] CLI Basics: Add `bee secret set|get|list` with `--scope`, `--global`, `--stdin`, and `--backend`.
- [x] Env Overrides: Detect and warn when env vars shadow stored secrets.
- [x] Limits: Enforce max size (8KB) and mask values in listings.
- [x] Permissions: Ensure secure file creation (0600), atomic writes, and parent directory perms.
- [x] CI Behavior: Prefer file backend in CI; env/flag override.
- [ ] Errors: Expand remediation messages and unify error codes.
- [ ] Audit Logs: Log operations without values; include scope/key and outcome only.
- [ ] Tests: Unit/integration tests for precedence, backends, and permissions.
- [ ] LLM Hooks: Helper to fetch `provider.*.api_key` by scope.
- [ ] Telemetry: Emit counters for set/get/list and override events (no values).
- [ ] Migration: `bee secret import --from .env --scope <hive>` with dry-run/confirm.
- [x] Docs: Architecture page for secrets and usage examples.
- [~] Packaging: Keyring optional (Rust feature, Python optional dep, JS dynamic import).

## Next Steps
- Add audit logging (without values) and telemetry hooks.
- Provide provider helpers for common API key lookups.
- Add targeted tests (file perms, precedence, scoping) when test harness is enabled.
