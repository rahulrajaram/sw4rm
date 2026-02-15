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

## Extension Index

| ID | Title | Status | Extends |
|----|-------|--------|---------|
| [SW4-001](./SW4-001-failure-semantics.md) | Failure Semantics | Draft | Core §17.5 |
| [SW4-002](./SW4-002-timeout-profiles.md) | Timeout Profiles | Draft | Core §5, OPERATIONAL_CONTRACTS |
| [SW4-003](./SW4-003-observability.md) | Observability | Draft | Core §4 |
| [SW4-004](./SW4-004-inter-swarm-composition.md) | Inter-Swarm Composition | Draft | Core §4, §7.2, §11, §17.6, §18.6, SW4-002, SW4-003 |
| [SW4-005](./SW4-005-spillover-routing.md) | Spillover Routing | Draft | SW4-004 §2.2, §9.3, §9.4 |

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

## Implementation Status (2026-02-15)

- Python: SW4-004/SW4-005 wire fields, caller redirect helper, gateway redirect-emitter helper, cancellation helper behavior, full SW4-004/SW4-005 conformance suites, and shared vector adapters.
- JS/TS: SW4-004/SW4-005 wire fields, caller redirect helper, gateway redirect-emitter helper, cancellation helper behavior, full SW4-004/SW4-005 conformance coverage, and shared vector adapters.
- Rust: SW4-004/SW4-005 wire fields, caller redirect helper, gateway redirect-emitter helper, cancellation helper behavior, full SW4-004/SW4-005 conformance coverage, and shared vector adapters.
- Common Lisp: SW4-004/SW4-005 wire fields, caller redirect helper, gateway redirect-emitter helper, cancellation helper behavior, full SW4-004/SW4-005 conformance coverage, and shared vector adapters.

See `sdks/SDK_IMPLEMENTATION_PROGRESS.md` for the authoritative cross-SDK capability matrix.

## Extension Lifecycle

1. **Draft**: Initial proposal, open for feedback
2. **Candidate**: Implementation experience gathered
3. **Stable**: Proven in production, normative
4. **Deprecated**: Superseded by newer extension

## Contributing

To propose a new extension:

1. Create `SW4-NNN-title.md` following the template
2. Assign the next available ID
3. Submit for review
4. Gather implementation feedback

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

*Last updated: 2026-02-15*
