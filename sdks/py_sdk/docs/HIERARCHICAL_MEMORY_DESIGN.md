# Hierarchical Memory System for SW4RM

## Overview

Design a memory system for SW4RM that supports:
- **Scoped promotion**: Child swarm memory isolated; selected memories promoted to parent on completion
- **Three memory types**: Task graph + semantic embeddings + episodic traces
- **Explicit channels**: Opt-in shared memory regions between sibling swarms
- **Scale**: 1K-10K tasks per project

## Architecture Decision

**Hybrid approach:**
1. **Task Graph** → Beads CLI wrapper (`bd --json`). Most decoupled, proven 20K scale.
2. **Semantic Memory** → Self-hosted vector store (Qdrant or pgvector). Option to build custom if needed.
3. **Episodic Memory** → Custom SQLite (co-located, simple append-only)
4. **Channels** → Custom SQLite (lightweight reference sharing)
5. **Episode Compression** → Hybrid: extractive for <50 events, LLM for complex episodes

## Scope Hierarchy Model

```
scope_id := <tenant>/<project>/<phase>[/<swarm_path>*]

Example:
  acme/webapp/design                    # Phase scope
  acme/webapp/design/ui-review          # Child swarm
  acme/webapp/design/ui-review/audit    # Grandchild
```

**Promotion semantics:**
- Child memory fully isolated during execution
- On completion, agent calls `promote(memory_ids, target_scope)`
- Promoted items get new scope but retain origin reference

## Data Models

### MemoryScope
```python
@dataclass
class MemoryScope:
    scope_id: str                      # "acme/webapp/design"
    parent_scope_id: Optional[str]
    status: ScopeStatus                # active | completing | closed
    inherit_from_parent: bool = True
    channel_subscriptions: Set[str] = field(default_factory=set)
```

### MemoryChannel (for sibling sharing)
```python
@dataclass
class MemoryChannel:
    channel_id: str
    owner_scope_id: str
    member_scope_ids: Set[str]
    visibility: str = "members"        # members | parent | public
    write_mode: str = "owner"          # owner | members
    task_refs: List[str]
    semantic_refs: List[str]
    episode_refs: List[str]
```

### Episode (episodic trace)
```python
@dataclass
class Episode:
    episode_id: str
    scope_id: str
    events: List[EpisodeEvent]
    summary: str                       # Generated on close
    compressed: bool = False           # True after promotion
```

## Database Schema

```sql
-- Extend Beads issues table
ALTER TABLE issues ADD COLUMN scope_id TEXT NOT NULL DEFAULT '';
ALTER TABLE issues ADD COLUMN promoted_from TEXT;
CREATE INDEX idx_issues_scope ON issues(scope_id);

-- New tables (co-located in beads.db)
CREATE TABLE memory_scopes (
    scope_id TEXT PRIMARY KEY,
    parent_scope_id TEXT,
    status TEXT DEFAULT 'active',
    inherit_from_parent BOOLEAN DEFAULT TRUE,
    channel_subscriptions TEXT,  -- JSON array
    created_at TIMESTAMP,
    closed_at TIMESTAMP
);

CREATE TABLE memory_channels (
    channel_id TEXT PRIMARY KEY,
    owner_scope_id TEXT NOT NULL,
    member_scope_ids TEXT,  -- JSON array
    visibility TEXT DEFAULT 'members',
    write_mode TEXT DEFAULT 'owner',
    task_refs TEXT,
    semantic_refs TEXT,
    episode_refs TEXT
);

CREATE TABLE episodes (
    episode_id TEXT PRIMARY KEY,
    scope_id TEXT NOT NULL,
    title TEXT,
    summary TEXT,
    started_at TIMESTAMP,
    ended_at TIMESTAMP,
    is_active BOOLEAN DEFAULT TRUE,
    compressed BOOLEAN DEFAULT FALSE,
    promoted_from TEXT
);

CREATE TABLE episode_events (
    event_id TEXT PRIMARY KEY,
    episode_id TEXT NOT NULL,
    event_type TEXT NOT NULL,
    timestamp TIMESTAMP NOT NULL,
    agent_id TEXT,
    task_id TEXT,
    action TEXT,
    input_data TEXT,
    output_data TEXT,
    success BOOLEAN,
    error_message TEXT,
    FOREIGN KEY (episode_id) REFERENCES episodes(episode_id)
);
```

## SW4RM Integration Points

### 1. PersistenceBackend (sw4rm/persistence.py)
Implement `HierarchicalMemoryBackend`:
- `save_records()` → Write to episodic store
- `load_records()` → Query scope hierarchy
- `clear()` → Scope-aware cleanup

### 2. SharedContextManager (sw4rm/shared_context.py)
Extend with `HierarchicalSharedContextManager`:
- Contexts backed by semantic store
- Scope-aware retrieval with parent fallback

### 3. HandoffContext (sw4rm/handoff/context.py)
Add `ScopedHandoffContext`:
- Include `promote_tasks`, `promote_semantics`, `promote_episodes` refs
- Execute promotion during handoff

### 4. WorkflowEngine (sw4rm/workflow/engine.py)
Wrap with `ScopedWorkflowEngine`:
- Create child scope per workflow execution
- Auto-promote on workflow completion
- Track episodes for workflow lifecycle

## Key Algorithms

### Scope Resolution (memory reads)
```
1. Query current scope
2. If inherit_from_parent: recurse to parent
3. Query subscribed channels
4. Deduplicate and rank by relevance
```

### Promotion (memory writes to parent)
```
1. Validate source is direct child of target
2. For tasks: copy with promoted_from reference
3. For semantics: add to parent scope with origin metadata
4. For episodes: compress to summary, copy key events only
```

## Files to Create/Modify

| File | Action | Purpose |
|------|--------|---------|
| `sw4rm/memory/__init__.py` | Create | Memory module |
| `sw4rm/memory/scope.py` | Create | MemoryScope, ScopeManager |
| `sw4rm/memory/beads_cli.py` | Create | BeadsCLI wrapper (shell to `bd --json`) |
| `sw4rm/memory/task_store.py` | Create | ScopedTaskStore (uses BeadsCLI) |
| `sw4rm/memory/semantic_store.py` | Create | ScopedSemanticStore (Qdrant/pgvector) |
| `sw4rm/memory/episodic_store.py` | Create | EpisodicStore (SQLite) |
| `sw4rm/memory/channels.py` | Create | ChannelManager |
| `sw4rm/memory/backend.py` | Create | HierarchicalMemoryBackend |
| `sw4rm/memory/compression.py` | Create | Episode compression (extractive + LLM hybrid) |
| `sw4rm/shared_context.py` | Modify | Add hierarchical support |
| `sw4rm/workflow/engine.py` | Modify | Add scope lifecycle |

## Verification Plan

1. **Unit tests**: Each store (task, semantic, episodic) with scope isolation
2. **Integration test**: Nested workflow with promotion
3. **Scale test**: 10K tasks across 100 scopes
4. **Channel test**: Sibling swarms sharing via channel

```bash
# Run tests
pytest sw4rm/memory/tests/ -v

# Scale benchmark
python -m sw4rm.memory.benchmark --tasks 10000 --scopes 100
```

## Decisions Made

1. **Semantic store**: Self-hosted (Qdrant or pgvector). Open to building custom vector store using AI agent loop if Mem0 doesn't fit.
2. **Beads integration**: CLI wrapper (`bd --json`). Most decoupled. Accepts latency tradeoff for clean separation.
3. **Episode compression**: Hybrid. Extractive for <50 events (fast, deterministic). LLM summarization for complex episodes.

## Beads CLI Wrapper Design

```python
import subprocess
import json
from typing import Optional, List, Dict, Any

class BeadsCLI:
    """Wrapper around bd CLI for task graph operations."""

    def __init__(self, repo_path: str):
        self.repo_path = repo_path

    def _run(self, args: List[str]) -> Dict[str, Any]:
        cmd = ["bd", "--json"] + args
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            cwd=self.repo_path
        )
        if result.returncode != 0:
            raise BeadsError(result.stderr)
        return json.loads(result.stdout)

    def create_task(self, title: str, **kwargs) -> str:
        args = ["create", title]
        if kwargs.get("priority"):
            args += ["-p", str(kwargs["priority"])]
        if kwargs.get("parent"):
            args += ["--parent", kwargs["parent"]]
        result = self._run(args)
        return result["id"]

    def get_ready_work(self, limit: int = 10) -> List[Dict]:
        return self._run(["ready", "-n", str(limit)])

    def add_dependency(self, blocker_id: str, blocked_id: str) -> None:
        self._run(["dep", "add", blocker_id, blocked_id])

    def close_task(self, task_id: str, reason: str = "") -> None:
        args = ["close", task_id]
        if reason:
            args += ["-m", reason]
        self._run(args)

    def show_task(self, task_id: str) -> Dict[str, Any]:
        return self._run(["show", task_id])
```

## Semantic Store Options

### Option A: Qdrant (Recommended for scale)
```python
from qdrant_client import QdrantClient
from qdrant_client.models import Distance, VectorParams

client = QdrantClient(host="localhost", port=6333)
client.create_collection(
    collection_name="sw4rm_memories",
    vectors_config=VectorParams(size=1536, distance=Distance.COSINE)
)
```

### Option B: pgvector (If Postgres already in stack)
```sql
CREATE EXTENSION vector;
CREATE TABLE memories (
    id TEXT PRIMARY KEY,
    scope_id TEXT NOT NULL,
    content TEXT,
    embedding vector(1536),
    metadata JSONB
);
CREATE INDEX ON memories USING ivfflat (embedding vector_cosine_ops);
```

### Option C: Custom Build
If existing solutions don't fit, build custom semantic store:
- Embeddings via OpenAI/local model
- SQLite with numpy for vector ops (small scale)
- FAISS for larger scale in-process search
