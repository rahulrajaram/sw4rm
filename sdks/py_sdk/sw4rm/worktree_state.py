from __future__ import annotations

from dataclasses import dataclass
from typing import Optional, Dict, Any

# Re-export the enhanced implementations
from .worktree_policies import (
    WorktreeBinding,
    PersistentWorktreeState,
    DefaultWorktreePolicy,
    WorktreePersistence,
    WorktreePolicyHook,
    BindingAction
)


# Keep the simple in-memory implementation for backwards compatibility
@dataclass
class LegacyWorktreeBinding:
    repo_id: str
    worktree_id: str


class WorktreeState:
    """Legacy in-memory worktree state. Use PersistentWorktreeState for new code."""
    
    def __init__(self) -> None:
        self._binding: LegacyWorktreeBinding | None = None

    def bind(self, repo_id: str, worktree_id: str) -> None:
        self._binding = LegacyWorktreeBinding(repo_id=repo_id, worktree_id=worktree_id)

    def unbind(self) -> None:
        self._binding = None

    def current(self) -> LegacyWorktreeBinding | None:
        return self._binding

