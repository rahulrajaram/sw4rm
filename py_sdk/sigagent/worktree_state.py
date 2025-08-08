from __future__ import annotations

from dataclasses import dataclass


@dataclass
class WorktreeBinding:
    repo_id: str
    worktree_id: str


class WorktreeState:
    def __init__(self) -> None:
        self._binding: WorktreeBinding | None = None

    def bind(self, repo_id: str, worktree_id: str) -> None:
        self._binding = WorktreeBinding(repo_id=repo_id, worktree_id=worktree_id)

    def unbind(self) -> None:
        self._binding = None

    def current(self) -> WorktreeBinding | None:
        return self._binding

