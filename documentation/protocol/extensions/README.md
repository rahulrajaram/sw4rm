# SW4RM Protocol Extensions

This directory contains optional protocol extensions that build on the core SW4RM specification. Extensions are identified by the prefix `SW4-NNN` and follow a consistent structure.

## Extension Index

| ID | Title | Status | Extends |
|----|-------|--------|---------|
| [SW4-001](./SW4-001-failure-semantics.md) | Failure Semantics | Draft | Core §17.5 |
| [SW4-002](./SW4-002-timeout-profiles.md) | Timeout Profiles | Draft | Core §5, OPERATIONAL_CONTRACTS |
| [SW4-003](./SW4-003-observability.md) | Observability | Draft | Core §4 |

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

*Last updated: 2026-01-10*
