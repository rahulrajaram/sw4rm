# SW4RM Protocol Extensions

This directory contains optional protocol extensions that build on the core SW4RM specification. Extensions are identified by the prefix `SW4-NNN` and follow a consistent structure.

Related documents:

- [Protocol Specification](../index.md)
- [Protocol RFC](../spec.md)
- [SDK Extensions](../sdk_extensions.md) (non-normative SDK features)

## Versioned Extension Releases

The core specification (`spec.md`) is a static document: only the version number changes. All normative protocol evolution is tracked in versioned extension release files, one per spec version. Each file summarizes what extensions shipped or changed in that release.

| Spec Version | Release File | Date |
|---|---|---|
| 0.5.0 | [v0.5.0.md](./v0.5.0.md) | 2026-01-04 |
| 0.6.0 | [v0.6.0.md](./v0.6.0.md) | 2026-02-15 |

## Draft Proposal and Version-Bump Policy

The repository distinguishes between tracked extension proposal drafts and shipped protocol releases:

- `documentation/protocol/extensions/SW4-*.md` files are tracked draft or rejected proposal documents. They may evolve without changing the core protocol version by themselves.
- `documentation/protocol/extensions/v0.N.0.md` files are shipped release summaries. Updating one is a normative protocol release action and must accompany a version bump.
- `documentation/protocol/spec.md` and `protos/` remain version-gated normative surfaces.
- `documentation/protocol/extensions/index.md` is catalog and policy documentation; updating it does not, by itself, trigger a protocol version bump.

This policy matches the pre-commit hook: proposal drafts stay reviewable in version control, while shipped release files and core normative surfaces remain semver-gated.

## Extension Index

| ID | Title | Status | Extends |
|----|-------|--------|---------|
| [SW4-001](./SW4-001-failure-semantics.md) | Failure Semantics | Draft | Core §17.5 |
| [SW4-002](./SW4-002-timeout-profiles.md) | Timeout Profiles | Draft | Core §5, OPERATIONAL_CONTRACTS |
| [SW4-003](./SW4-003-observability.md) | Observability | Draft | Core §4 |
| [SW4-004](./SW4-004-inter-swarm-composition.md) | Inter-Swarm Composition | Draft | Core §4, §7.2, §11, §17.6, §18.6, SW4-002, SW4-003 |
| [SW4-005](./SW4-005-spillover-routing.md) | Spillover Routing | Draft | SW4-004 §2.2, §9.3, §9.4 |
| [SW4-006](./SW4-006-resource-aware-scheduling.md) | Resource-Aware Scheduling | Rejected | — |
| [SW4-007](./SW4-007-explicit-request-response-semantics.md) | Explicit Request/Response Semantics | Draft | Core §10, §11, §13, §21 |
| [SW4-008](./SW4-008-group-addressing-pubsub.md) | Group Addressing and Pub/Sub | Planning | Core §11, §14, §21 |
| [SW4-009](./SW4-009-workflow-v2-compensation-branching.md) | Workflow v2 Compensation and Branching | Planning | Core §17.7 |
| [SW4-010](./SW4-010-inference-engine-protocol.md) | Inference Engine Protocol | Planning | Core §9.3, §20, §23 |
| [SW4-011](./SW4-011-scheduler-ha.md) | Scheduler High Availability | Planning | Core §4, §14, §19, §21 |
| [SW4-012](./SW4-012-agent-capability-versioning.md) | Agent Capability Versioning | Rejected | Core §14 |
| [SW4-013](./SW4-013-security-wire-profile.md) | Security Wire Profile | Planning | Core §6, §23 |
| [SW4-014](./SW4-014-dynamic-swarm-spawning.md) | Dynamic Swarm Spawning | Draft | Core §4, §17.6, §17.7 |
| [SW4-015](./SW4-015-a2a-gateway-binding.md) | A2A Gateway Binding | Draft | Core §3.9, §11, SW4-007 |

## Implementation Profile Cross-Links

- [SW4-004 Implementation Profile](./SW4-004-inter-swarm-composition.md#94-sw4-004sw4-005-implementation-profile-cross-sdk-required-behavior): §9.4 SW4-004/SW4-005 implementation profile (cross-SDK required behavior).
- [SW4-005 Implementation Profile](./SW4-005-spillover-routing.md#15-sw4-004sw4-005-implementation-profile): §15 SW4-004/SW4-005 implementation profile alignment.
- [SW4-004 Conformance Outline](./SW4-004-inter-swarm-composition.md#10-conformance-test-outline): cancellation cascade/grace clamp, spillover-disabled `OVERLOADED` fallback, and canonical redirect target normalization.
- [SW4-005 Conformance Outline](./SW4-005-spillover-routing.md#11-conformance-test-outline): redirect emission shape, spillover-disable fallback behavior, and canonical redirect target handling.

## Extension Philosophy

The core SW4RM specification is intentionally minimal, defining only the essential coordination primitives. Extensions provide:

- **Production hardening**: Failure semantics, timeout tuning, observability
- **Optional features**: Advanced consensus, security enhancements
- **Implementation guidance**: Best practices, patterns, anti-patterns

Extensions are OPTIONAL unless explicitly required by a deployment profile.

## Conformance Levels

Implementations may claim conformance to specific extensions:

- **Core Only**: Implements core spec, no extensions
- **Core + SW4-001**: Adds failure semantics
- **Core + SW4-001 + SW4-002 + SW4-003**: Production-ready profile
- **Core + SW4-001..SW4-004**: Production-ready with inter-swarm composition
- **Core + SW4-001..SW4-005**: Inter-swarm composition + spillover routing (wire compatibility + helper behavior where implemented)

## Implementation Status (2026-03-24)

| SDK | Status | Notes |
|---|---|---|
| Python | Complete | SW4-004/SW4-005 wire fields, caller redirect helper, gateway redirect-emitter helper, cancellation helper behavior, full conformance suites, and shared vector adapters. |
| JS/TS | Complete | SW4-004/SW4-005 wire fields, caller redirect helper, gateway redirect-emitter helper, cancellation helper behavior, full conformance coverage, and shared vector adapters. |
| Rust | Complete | SW4-004/SW4-005 wire fields, caller redirect helper, gateway redirect-emitter helper, cancellation helper behavior, full conformance coverage, and shared vector adapters. |
| Common Lisp | Complete | SW4-004/SW4-005 wire fields, caller redirect helper, gateway redirect-emitter helper, cancellation helper behavior, full conformance coverage, and shared vector adapters. |
| Elixir | Complete | SW4-004/SW4-005 wire fields, caller redirect helper, gateway redirect-emitter helper, cancellation helper behavior, and conformance coverage aligned to the public profile. |

This table is the canonical public cross-SDK implementation status; supporting evidence is maintained in `artifacts/verification/`.

## Extension Lifecycle

1. **Draft**: Initial proposal, open for feedback
2. **Candidate**: Implementation experience gathered
3. **Stable**: Proven in production, normative
4. **Deprecated**: Superseded by newer extension
5. **Rejected**: Evaluated and determined out of scope

## Contributing

To propose a new extension:

1. Create `SW4-NNN-title.md` following the template
2. Assign the next available ID
3. Submit for review
4. Gather implementation feedback

## MkDocs Navigation

Tracked extension drafts and shipped extension release files are intentionally surfaced in MkDocs navigation for direct review and cross-linking.

## Template

```markdown
# SW4-NNN: Title

**Status:** Draft
**Version:** 0.1.0
**Date:** YYYY-MM-DD
**Extends:** Core Spec §X.Y

## Abstract
[One paragraph summary]

## Motivation
[Why this extension is needed]

## Specification
[Normative requirements]

## Implementation Requirements
[MUST/SHOULD/MAY requirements]

## Compatibility
[Backward compatibility notes]

## References
[Related specs and extensions]
```

---

*Last updated: 2026-03-28*
