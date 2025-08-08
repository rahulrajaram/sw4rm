from __future__ import annotations

from dataclasses import dataclass, field
from typing import Optional, Dict, Any
import time


@dataclass
class WorktreeBindingState:
    agent_id: str
    repo_id: Optional[str] = None
    worktree_id: Optional[str] = None
    bound: bool = False
    last_change_ms: int = field(default_factory=lambda: int(time.time() * 1000))

    def bind(self, repo_id: str, worktree_id: str) -> None:
        self.repo_id = repo_id
        self.worktree_id = worktree_id
        self.bound = True
        self.last_change_ms = int(time.time() * 1000)

    def unbind(self) -> None:
        self.repo_id = None
        self.worktree_id = None
        self.bound = False
        self.last_change_ms = int(time.time() * 1000)

    def switch(self, repo_id: str, worktree_id: str) -> None:
        self.bind(repo_id, worktree_id)

    def status(self) -> Dict[str, Any]:
        return {
            "agent_id": self.agent_id,
            "repo_id": self.repo_id or "",
            "worktree_id": self.worktree_id or "",
            "bound": self.bound,
            "last_change_ms": self.last_change_ms,
        }

