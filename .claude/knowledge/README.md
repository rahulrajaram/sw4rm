# SW4RM Knowledge Index

This directory contains the **token-efficient memory system** for the `swarm-knowledge-guardian` agent.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    Agent Context Window                         │
├─────────────────────────────────────────────────────────────────┤
│  ┌──────────────┐   Load First    ┌────────────────────┐       │
│  │  manifest    │ ───────────────▶│  Agent understands │       │
│  │   .yaml      │   (~2KB)        │  what exists       │       │
│  └──────────────┘                 └────────────────────┘       │
│         │                                                       │
│         ▼                                                       │
│  ┌──────────────┐   Load Second   ┌────────────────────┐       │
│  │  glossary    │ ───────────────▶│  Agent knows       │       │
│  │   .yaml      │   (~3KB)        │  correct terms     │       │
│  └──────────────┘                 └────────────────────┘       │
│         │                                                       │
│         ▼                                                       │
│  ┌──────────────┐   Load Third    ┌────────────────────┐       │
│  │  cross-refs  │ ───────────────▶│  Agent knows       │       │
│  │   .yaml      │   (~4KB)        │  relationships     │       │
│  └──────────────┘                 └────────────────────┘       │
│         │                                                       │
│         ▼                                                       │
│  ┌──────────────┐   Check Hashes  ┌────────────────────┐       │
│  │  checksums   │ ───────────────▶│  Agent knows       │       │
│  │   .yaml      │   (~1KB)        │  what's changed    │       │
│  └──────────────┘                 └────────────────────┘       │
│         │                                                       │
│         ▼                                                       │
│  ┌──────────────┐   On-Demand     ┌────────────────────┐       │
│  │  summaries/  │ ───────────────▶│  Agent loads       │       │
│  │   *.md       │   (~1KB each)   │  compressed context│       │
│  └──────────────┘                 └────────────────────┘       │
│         │                                                       │
│         ▼                                                       │
│  ┌──────────────┐   Only When     ┌────────────────────┐       │
│  │  Source      │   Verification  │  Full source only  │       │
│  │  Files       │   Needed        │  for verification  │       │
│  └──────────────┘                 └────────────────────┘       │
└─────────────────────────────────────────────────────────────────┘
```

## Token Efficiency Strategy

### Problem
The SW4RM knowledge base spans:
- 1 large spec file (~100KB, ~25K tokens)
- 20+ documentation files (~200KB total)
- 3 SDKs with source code (~500KB total)
- 20+ proto files (~50KB total)

Loading everything into context is impossible (~200K+ tokens).

### Solution: Hierarchical Knowledge Compression

**Layer 1: Manifest (~2KB)**
- Lists ALL knowledge sources
- Describes what each contains
- Provides section-level granularity
- Agent loads this FIRST

**Layer 2: Glossary (~3KB)**
- Canonical terminology
- Never/always rules
- Enables terminology checking without reading sources

**Layer 3: Cross-References (~4KB)**
- Maps concept → sources
- Defines authority hierarchy
- Lists verification points
- Enables contradiction detection without reading both sources

**Layer 4: Checksums (~1KB)**
- Content hashes for all sources
- Enables incremental analysis
- Skip unchanged files

**Layer 5: Summaries (~1KB each, on-demand)**
- Pre-compressed section summaries
- Key points, not full text
- Updated when checksum changes

**Layer 6: Source Files (only when needed)**
- Only read for verification
- Only read changed sections
- Quote exact text for evidence

### Context Usage

| Operation | Tokens Required |
|-----------|-----------------|
| Full knowledge base | ~200,000 |
| Knowledge index only | ~10,000 |
| Index + relevant summaries | ~15,000 |
| Index + verification reads | ~25,000 |

**Result: 8-20x reduction in context usage**

## Files

| File | Purpose | Size |
|------|---------|------|
| `manifest.yaml` | Master knowledge map | ~2KB |
| `glossary.yaml` | Canonical terminology | ~3KB |
| `cross-references.yaml` | Document relationships | ~4KB |
| `checksums.yaml` | Content hashes for drift detection | ~1KB |
| `summaries/` | Pre-compressed section summaries | ~1KB each |

## Maintenance

The `swarm-knowledge-guardian` agent is responsible for maintaining this index:

1. **After each audit session**: Update checksums for analyzed files
2. **When discovering new terms**: Add to glossary
3. **When finding new relationships**: Add to cross-references
4. **When content changes**: Regenerate affected summaries

## Usage by Other Agents

Other agents can use this knowledge index for context assembly:

```yaml
# In agent prompt:
## Context Assembly (Before Acting)
1. Read `.claude/knowledge/manifest.yaml` for knowledge map
2. Read `.claude/knowledge/glossary.yaml` for terminology
3. Load relevant summaries based on task
```

## Extending the System

### Adding New Knowledge Sources

1. Add entry to `manifest.yaml` under appropriate category
2. Add cross-references in `cross-references.yaml`
3. Run guardian to generate checksums and summaries

### Adding New Terms

1. Add to `glossary.yaml` with canonical form
2. List aliases and never-use forms
3. Reference first-defined location

### Tracking New Relationships

1. Add concept to `cross-references.yaml`
2. List authoritative source
3. List all other locations
4. Add verification points
