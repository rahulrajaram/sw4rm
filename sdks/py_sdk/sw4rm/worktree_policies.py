"""Worktree binding data structures and policy interfaces.

This module provides the core data structures and interfaces for worktree
binding management. It does NOT include policy implementations - those
should be provided by specialized implementations as needed.

Includes TTL enforcement for BOUND_NON_HOME state per spec section 16.
When an agent is bound to a non-home worktree via approve_switch(),
a timer automatically reverts the binding to the home worktree after
the TTL expires.
"""

from __future__ import annotations

import json
import threading
import time as _time
from dataclasses import dataclass, asdict
from pathlib import Path
from typing import Dict, Optional, Any, Protocol, Callable
from enum import Enum


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
    metadata: Optional[Dict[str, Any]] = None

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
    """Protocol interface for worktree policy hooks.
    
    Implementations can provide custom policy logic by implementing
    this protocol. All methods are optional - provide only the hooks
    you need for your specific policy requirements.
    """

    def before_bind(self, repo_id: str, worktree_id: str, current_binding: Optional[WorktreeBinding]) -> bool:
        """Called before binding to a worktree.
        
        Args:
            repo_id: Repository identifier
            worktree_id: Worktree identifier
            current_binding: Current binding if any
            
        Returns:
            True to allow binding, False to reject
        """
        ...

    def after_bind(self, binding: WorktreeBinding) -> None:
        """Called after successful binding.
        
        Args:
            binding: The newly created binding
        """
        ...

    def before_unbind(self, binding: WorktreeBinding) -> bool:
        """Called before unbinding.
        
        Args:
            binding: The binding being removed
            
        Returns:
            True to allow unbinding, False to reject
        """
        ...

    def after_unbind(self, former_binding: WorktreeBinding) -> None:
        """Called after successful unbinding.
        
        Args:
            former_binding: The binding that was removed
        """
        ...

    def on_bind_error(self, repo_id: str, worktree_id: str, error: Exception) -> None:
        """Called when binding fails.

        Args:
            repo_id: Repository identifier that failed to bind
            worktree_id: Worktree identifier that failed to bind
            error: The exception that occurred
        """
        ...


class DefaultWorktreePolicy:
    """Default no-op policy that allows all operations."""

    def before_bind(self, repo_id: str, worktree_id: str, current_binding: Optional[WorktreeBinding]) -> bool:
        """Allow all bindings."""
        return True

    def after_bind(self, binding: WorktreeBinding) -> None:
        """No-op after bind."""
        pass

    def before_unbind(self, binding: WorktreeBinding) -> bool:
        """Allow all unbindings."""
        return True

    def after_unbind(self, former_binding: WorktreeBinding) -> None:
        """No-op after unbind."""
        pass

    def on_bind_error(self, repo_id: str, worktree_id: str, error: Exception) -> None:
        """No-op on error."""
        pass


class WorktreePersistence:
    """JSON file-based persistence for worktree bindings."""

    def __init__(self, file_path: str = "sw4rm_worktree.json"):
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
    """Worktree state with persistent storage, policy hooks, and TTL enforcement.

    Supports the full spec section 16 worktree state machine including:
    - UNBOUND -> BOUND_HOME (via bind)
    - BOUND_HOME -> SWITCH_PENDING (via request_switch)
    - SWITCH_PENDING -> BOUND_NON_HOME (via approve_switch, with TTL)
    - SWITCH_PENDING -> BOUND_HOME (via reject_switch)
    - BOUND_NON_HOME -> BOUND_HOME (via revert_to_home or TTL expiry)
    - Any -> UNBOUND (via unbind)

    When approve_switch is called with a TTL, a background timer automatically
    reverts the agent to its home worktree when the TTL expires, matching the
    JS SDK behavior.
    """

    def __init__(
        self,
        *,
        persistence: Optional[WorktreePersistence] = None,
        policy: Optional[WorktreePolicyHook] = None
    ):
        self._persistence = persistence or WorktreePersistence()
        self._policy = policy or DefaultWorktreePolicy()
        self._binding: Optional[WorktreeBinding] = None

        # TTL enforcement for BOUND_NON_HOME (spec section 16)
        self._home_binding: Optional[WorktreeBinding] = None
        self._switch_ttl_ms: Optional[int] = None
        self._switch_timer: Optional[threading.Timer] = None
        self._state: str = "UNBOUND"

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
        """Bind to a worktree with policy validation (UNBOUND -> BOUND_HOME).

        Args:
            repo_id: Repository identifier to bind to.
            worktree_id: Worktree identifier to bind to (becomes home worktree).
            metadata: Optional metadata to attach to the binding.

        Returns:
            True if binding succeeded, False if rejected by policy.
        """
        try:
            # Call before_bind hook
            if not self._policy.before_bind(repo_id, worktree_id, self._binding):
                return False

            # Create new binding
            new_binding = WorktreeBinding(
                repo_id=repo_id,
                worktree_id=worktree_id,
                bound_at=int(_time.time()),
                metadata=metadata or {}
            )

            # Update state
            self._binding = new_binding
            self._home_binding = WorktreeBinding(
                repo_id=repo_id,
                worktree_id=worktree_id,
                bound_at=new_binding.bound_at,
                metadata=dict(metadata) if metadata else {},
            )
            self._state = "BOUND_HOME"
            self._save_to_persistence()

            # Call after_bind hook
            self._policy.after_bind(new_binding)

            return True

        except Exception as e:
            self._state = "BIND_FAILED"
            self._policy.on_bind_error(repo_id, worktree_id, e)
            return False

    def unbind(self) -> bool:
        """Unbind from current worktree with policy validation (Any -> UNBOUND)."""
        if not self._binding:
            return True

        try:
            # Call before_unbind hook
            if not self._policy.before_unbind(self._binding):
                return False

            self._clear_switch_timer()
            former_binding = self._binding
            self._binding = None
            self._home_binding = None
            self._state = "UNBOUND"
            self._switch_ttl_ms = None
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

    def request_switch(self, target_repo_id: str, target_worktree_id: str) -> bool:
        """Request switch to a non-home worktree (BOUND_HOME -> SWITCH_PENDING).

        Requires approval via approve_switch() or rejection via reject_switch()
        before taking effect.

        Args:
            target_repo_id: Repository identifier to switch to.
            target_worktree_id: Worktree identifier to switch to.

        Returns:
            True if the request was accepted, False otherwise.
        """
        if self._state != "BOUND_HOME":
            return False
        self._pending_repo_id = target_repo_id
        self._pending_worktree_id = target_worktree_id
        self._state = "SWITCH_PENDING"
        return True

    def approve_switch(self, ttl_ms: int = 300_000) -> bool:
        """Approve a pending switch (SWITCH_PENDING -> BOUND_NON_HOME).

        Sets up a TTL timer that automatically reverts the agent to its home
        worktree when the TTL expires, matching the JS SDK behavior per
        spec section 16.

        Args:
            ttl_ms: Time-to-live in milliseconds before auto-reverting to
                    BOUND_HOME. Defaults to 300000 (5 minutes).

        Returns:
            True if the approval succeeded, False if not in SWITCH_PENDING state.
        """
        if self._state != "SWITCH_PENDING":
            return False

        # Save current binding as home
        if self._binding and self._home_binding is None:
            self._home_binding = WorktreeBinding(
                repo_id=self._binding.repo_id,
                worktree_id=self._binding.worktree_id,
                bound_at=self._binding.bound_at,
                metadata=dict(self._binding.metadata) if self._binding.metadata else {},
            )

        # Bind to the pending target
        pending_repo = getattr(self, "_pending_repo_id", "")
        pending_wt = getattr(self, "_pending_worktree_id", "")
        self._binding = WorktreeBinding(
            repo_id=pending_repo,
            worktree_id=pending_wt,
            bound_at=int(_time.time()),
        )
        self._state = "BOUND_NON_HOME"
        self._switch_ttl_ms = ttl_ms
        self._save_to_persistence()

        # Set up TTL auto-revert timer
        self._clear_switch_timer()
        if ttl_ms > 0:
            self._switch_timer = threading.Timer(
                ttl_ms / 1000.0,
                self.revert_to_home,
            )
            self._switch_timer.daemon = True
            self._switch_timer.start()

        return True

    def reject_switch(self) -> bool:
        """Reject a pending switch (SWITCH_PENDING -> BOUND_HOME).

        Returns the agent to its home worktree binding.

        Returns:
            True if the rejection succeeded, False if not in SWITCH_PENDING state.
        """
        if self._state != "SWITCH_PENDING":
            return False

        # Restore home binding
        if self._home_binding:
            self._binding = self._home_binding
        self._state = "BOUND_HOME"
        self._save_to_persistence()
        return True

    def revert_to_home(self) -> None:
        """Revert from non-home to home worktree (BOUND_NON_HOME -> BOUND_HOME).

        Called automatically when TTL expires, or can be invoked manually.
        """
        self._clear_switch_timer()
        if self._state == "BOUND_NON_HOME" and self._home_binding:
            self._binding = self._home_binding
            self._state = "BOUND_HOME"
            self._switch_ttl_ms = None
            self._save_to_persistence()

    def _clear_switch_timer(self) -> None:
        """Cancel any pending TTL auto-revert timer."""
        if self._switch_timer is not None:
            self._switch_timer.cancel()
            self._switch_timer = None

    @property
    def state(self) -> str:
        """Get the current worktree state machine state.

        Returns:
            One of: UNBOUND, BOUND_HOME, SWITCH_PENDING, BOUND_NON_HOME, BIND_FAILED.
        """
        return self._state

    def current(self) -> Optional[WorktreeBinding]:
        """Get current binding."""
        return self._binding

    def is_bound(self) -> bool:
        """Check if currently bound to a worktree."""
        return self._binding is not None

    def status(self) -> Dict[str, Any]:
        """Get detailed status information."""
        if not self._binding:
            return {"bound": False, "state": self._state}

        result: Dict[str, Any] = {
            "bound": True,
            "state": self._state,
            "repo_id": self._binding.repo_id,
            "worktree_id": self._binding.worktree_id,
            "bound_at": self._binding.bound_at,
            "metadata": self._binding.metadata,
        }
        if self._home_binding:
            result["home_repo_id"] = self._home_binding.repo_id
            result["home_worktree_id"] = self._home_binding.worktree_id
        if self._switch_ttl_ms is not None:
            result["switch_ttl_ms"] = self._switch_ttl_ms
        return result

    def clear(self) -> None:
        """Clear binding and persistent storage."""
        self._clear_switch_timer()
        self._binding = None
        self._home_binding = None
        self._state = "UNBOUND"
        self._switch_ttl_ms = None
        self._persistence.clear()