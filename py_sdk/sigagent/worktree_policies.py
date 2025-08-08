from __future__ import annotations

import json
import os
from abc import ABC, abstractmethod
from dataclasses import dataclass, asdict
from pathlib import Path
from typing import Dict, List, Optional, Any, Callable, Protocol
from enum import Enum

from .persistence import PersistenceBackend, JSONFilePersistence


class BindingAction(Enum):
    """Actions that can be taken on worktree bindings."""
    BIND = "bind"
    UNBIND = "unbind"
    SWITCH = "switch"


@dataclass
class WorktreeBinding:
    """Represents a binding to a specific worktree."""
    repo_id: str
    worktree_id: str
    bound_at: int  # timestamp when binding was created
    metadata: Dict[str, Any] = None

    def __post_init__(self):
        if self.metadata is None:
            self.metadata = {}

    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary for serialization."""
        return asdict(self)

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> WorktreeBinding:
        """Create from dictionary."""
        return cls(**data)


class WorktreePolicyHook(Protocol):
    """Interface for worktree policy hooks."""

    def before_bind(self, repo_id: str, worktree_id: str, current_binding: Optional[WorktreeBinding]) -> bool:
        """Called before binding to a worktree. Return False to reject the binding."""
        ...

    def after_bind(self, binding: WorktreeBinding) -> None:
        """Called after successful binding."""
        ...

    def before_unbind(self, binding: WorktreeBinding) -> bool:
        """Called before unbinding. Return False to reject the unbind."""
        ...

    def after_unbind(self, former_binding: WorktreeBinding) -> None:
        """Called after successful unbinding."""
        ...

    def on_bind_error(self, repo_id: str, worktree_id: str, error: Exception) -> None:
        """Called when binding fails."""
        ...


class DefaultWorktreePolicy:
    """Default worktree policy with basic validation."""

    def __init__(self, *, allow_rebinding: bool = True, max_binding_age_hours: int = 24):
        self.allow_rebinding = allow_rebinding
        self.max_binding_age_hours = max_binding_age_hours

    def before_bind(self, repo_id: str, worktree_id: str, current_binding: Optional[WorktreeBinding]) -> bool:
        """Validate binding request."""
        # Reject if already bound and rebinding not allowed
        if current_binding and not self.allow_rebinding:
            return False
        
        # Basic validation
        if not repo_id or not worktree_id:
            return False
            
        return True

    def after_bind(self, binding: WorktreeBinding) -> None:
        """Log successful binding."""
        print(f"[Worktree] Bound to {binding.repo_id}/{binding.worktree_id}")

    def before_unbind(self, binding: WorktreeBinding) -> bool:
        """Always allow unbinding."""
        return True

    def after_unbind(self, former_binding: WorktreeBinding) -> None:
        """Log successful unbinding."""
        print(f"[Worktree] Unbound from {former_binding.repo_id}/{former_binding.worktree_id}")

    def on_bind_error(self, repo_id: str, worktree_id: str, error: Exception) -> None:
        """Log binding errors."""
        print(f"[Worktree] Failed to bind to {repo_id}/{worktree_id}: {error}")


class WorktreePersistence:
    """JSON file-based persistence for worktree bindings."""

    def __init__(self, file_path: str = "sigagent_worktree.json"):
        self.file_path = Path(file_path)

    def save_binding(self, binding: Optional[WorktreeBinding]) -> None:
        """Save current binding to file."""
        data = {
            "binding": binding.to_dict() if binding else None,
            "version": "1.0"
        }
        
        # Atomic write
        temp_path = self.file_path.with_suffix('.tmp')
        try:
            with open(temp_path, 'w') as f:
                json.dump(data, f, indent=2)
            temp_path.rename(self.file_path)
        except Exception:
            if temp_path.exists():
                temp_path.unlink()
            raise

    def load_binding(self) -> Optional[WorktreeBinding]:
        """Load binding from file."""
        if not self.file_path.exists():
            return None

        try:
            with open(self.file_path) as f:
                data = json.load(f)
            
            binding_data = data.get("binding")
            if binding_data:
                return WorktreeBinding.from_dict(binding_data)
            return None
        except (json.JSONDecodeError, KeyError, OSError):
            return None

    def clear(self) -> None:
        """Remove the persistence file."""
        if self.file_path.exists():
            self.file_path.unlink()


class PersistentWorktreeState:
    """Worktree state with persistent storage and policy hooks."""

    def __init__(
        self, 
        *, 
        persistence: Optional[WorktreePersistence] = None,
        policy: Optional[WorktreePolicyHook] = None
    ):
        self._persistence = persistence or WorktreePersistence()
        self._policy = policy or DefaultWorktreePolicy()
        self._binding: Optional[WorktreeBinding] = None
        
        # Load existing binding on initialization
        self._load_from_persistence()

    def _load_from_persistence(self) -> None:
        """Load binding from persistent storage."""
        try:
            self._binding = self._persistence.load_binding()
            if self._binding:
                print(f"[Worktree] Restored binding to {self._binding.repo_id}/{self._binding.worktree_id}")
        except Exception as e:
            print(f"[Worktree] Failed to load binding from persistence: {e}")
            self._binding = None

    def _save_to_persistence(self) -> None:
        """Save current binding to persistent storage."""
        try:
            self._persistence.save_binding(self._binding)
        except Exception as e:
            print(f"[Worktree] Failed to save binding to persistence: {e}")

    def bind(self, repo_id: str, worktree_id: str, metadata: Optional[Dict[str, Any]] = None) -> bool:
        """Bind to a worktree with policy validation."""
        try:
            # Call before_bind hook
            if not self._policy.before_bind(repo_id, worktree_id, self._binding):
                return False

            # Create new binding
            new_binding = WorktreeBinding(
                repo_id=repo_id,
                worktree_id=worktree_id,
                bound_at=int(__import__('time').time()),
                metadata=metadata or {}
            )

            # Update state
            self._binding = new_binding
            self._save_to_persistence()

            # Call after_bind hook
            self._policy.after_bind(new_binding)
            
            return True

        except Exception as e:
            self._policy.on_bind_error(repo_id, worktree_id, e)
            return False

    def unbind(self) -> bool:
        """Unbind from current worktree with policy validation."""
        if not self._binding:
            return True

        try:
            # Call before_unbind hook
            if not self._policy.before_unbind(self._binding):
                return False

            former_binding = self._binding
            self._binding = None
            self._save_to_persistence()

            # Call after_unbind hook
            self._policy.after_unbind(former_binding)
            
            return True

        except Exception as e:
            print(f"[Worktree] Failed to unbind: {e}")
            return False

    def switch(self, repo_id: str, worktree_id: str, metadata: Optional[Dict[str, Any]] = None) -> bool:
        """Switch to a different worktree (unbind then bind)."""
        # Unbind first if bound
        if self._binding and not self.unbind():
            return False
        
        # Then bind to new worktree
        return self.bind(repo_id, worktree_id, metadata)

    def current(self) -> Optional[WorktreeBinding]:
        """Get current binding."""
        return self._binding

    def is_bound(self) -> bool:
        """Check if currently bound to a worktree."""
        return self._binding is not None

    def status(self) -> Dict[str, Any]:
        """Get detailed status information."""
        if not self._binding:
            return {"bound": False}
        
        return {
            "bound": True,
            "repo_id": self._binding.repo_id,
            "worktree_id": self._binding.worktree_id,
            "bound_at": self._binding.bound_at,
            "metadata": self._binding.metadata
        }

    def clear(self) -> None:
        """Clear binding and persistent storage."""
        self._binding = None
        self._persistence.clear()