7. Secrets Management Milestone Context

7.1. Scope
This milestone introduces a secrets interface and CLI for setting, getting, and listing provider credentials and other sensitive values, with OS keyring backends where available and `.env` file fallback. It includes scoped secrets per hive and provider. It excludes remote secret stores.

7.2. Objectives
The objective is to store and retrieve secrets securely with least privilege and clear scoping. A secondary objective is to provide unambiguous error messages and guardrails when secrets are missing or mis-scoped.

7.3. Deliverables
Deliverables include a `Secrets` trait, keyring and file backends, CLI commands `bee secret set`, `bee secret get`, and `bee secret list`, and integration with LLM adapters to resolve API keys by scope. Warnings are emitted when environment variables override stored secrets.

7.4. Architecture and Interfaces
Secrets are identified by a tuple of scope (global or hive name) and key (e.g., `provider.anthropic.api_key`). The keyring backend uses platform-specific credential stores. The file backend writes an encrypted or permissions-restricted file. Resolution uses a precedence order: explicit CLI flag, environment variable, scoped secret, then global secret. All operations are synchronous and return typed errors.

7.5. Data Model
Secret records consist of scope, key, and value with created and updated timestamps. The file backend stores records as encrypted blobs or, where encryption is unavailable, as plaintext with mode 0600 and a clear warning at creation time.

7.6. Edge Cases and Failure Modes
Missing backends trigger a fallback with explicit acknowledgement. Permission errors abort with instructions to remediate. Secrets larger than a reasonable maximum are rejected. Attempts to read a secret from the wrong scope yield a descriptive error suggesting the existing scopes.

7.7. Testing Strategy
Unit tests cover resolution precedence, backend selection, and permission handling. Integration tests mock the keyring. CLI tests set and retrieve secrets in ephemeral scopes and assert no leakage to other scopes. Security tests ensure files are created with strict permissions and that environment overrides are logged.

7.8. Non-Goals
This milestone does not integrate with cloud secret managers or implement secret rotation policies beyond manual updates.

7.9. Dependencies
Optional use by LLM providers to retrieve API keys. No dependency on other milestones.

7.10. Migration and Rollout
The CLI ships with secrets commands disabled only on unsupported platforms. On Linux and macOS, keyring is preferred; on CI, file backend is used by default.

7.11. Operational Considerations
Secret access is audited via logs without values. Users can export and import secrets between hives using an encrypted archive format in a future milestone.


7.12. Action Items Checklist

- [ ] Core API: Define `Secrets` trait, `Scope`, `SecretKey`, `SecretValue`, and typed errors.
- [ ] Backends: Implement OS keyring backend; add file backend fallback with mode 0600.
- [ ] Scoping: Establish scope model (global | hive) and key schema `provider.<name>.<field>` with validation.
- [ ] Resolution: Implement precedence resolver (CLI > env > scoped > global) that returns value and source.
- [ ] CLI Basics: Add `bee secret set|get|list` with `--scope`, `--key`, `--json`, `--from-stdin`, and interactive prompts.
- [ ] Errors: Provide precise remediation messages for missing backend, permissions, and wrong-scope reads.
- [ ] Env Overrides: Detect and warn when environment variables shadow stored secrets; include `--no-warn` escape hatch.
- [ ] Limits: Enforce max size (e.g., 8KB) and reject binary/unsafe inputs; redact echoes.
- [ ] Permissions: Ensure secure file creation (umask, 0600), fsync, and directory permission checks.
- [ ] Audit Logs: Log operations without values; include scope/key and outcome only.
- [ ] CI Behavior: Prefer file backend in CI; add `--backend` override and clear warnings.
- [ ] Tests: Unit tests for precedence/scoping/backends; integration tests with mocked keyring; permission and env override tests.
- [ ] LLM Hooks: Provide helper to fetch `provider.*.api_key` by scope for adapters.
- [ ] Telemetry: Emit counters for set/get/list, override events, and backend selection (no values).
- [ ] Migration: Add `bee secret import --from .env --scope <hive>` with dry-run/confirm.
- [ ] Docs: Update CLI help, examples, troubleshooting (permissions, keyring availability, CI), and security notes.
- [ ] Packaging: Platform feature flags to toggle keyring; graceful disable on unsupported OS.


7.13. Documentation Constraints
- Do not modify the mkdocs configuration (`mkdocs.yml`).
- Place Bee/Secrets docs under `docs/bee/architecture/` when updating documentation for this milestone.
- The mkdocs site currently renders from `documentation/`; secrets docs under `docs/` are intentionally out-of-band and must not be wired into mkdocs navigation.
