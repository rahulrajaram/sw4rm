"""Example worktree policy implementations.

This module contains example policy implementations to demonstrate
how to extend the worktree management system with custom policies.
These are NOT part of the core SDK - they serve as examples only.
"""

from __future__ import annotations

from typing import Optional
from ..worktree_policies import WorktreeBinding, WorktreePolicyHook


class LoggingWorktreePolicy:
    """Example policy that logs all worktree operations.
    
    This demonstrates how to implement observability for worktree
    operations without enforcing specific business rules.
    """

    def before_bind(self, repo_id: str, worktree_id: str, current_binding: Optional[WorktreeBinding]) -> bool:
        """Log binding attempt and allow all bindings."""
        if current_binding:
            print(f"[Worktree] Switching from {current_binding.repo_id}/{current_binding.worktree_id} to {repo_id}/{worktree_id}")
        else:
            print(f"[Worktree] Binding to {repo_id}/{worktree_id}")
        return True

    def after_bind(self, binding: WorktreeBinding) -> None:
        """Log successful binding."""
        print(f"[Worktree] Successfully bound to {binding.repo_id}/{binding.worktree_id}")

    def before_unbind(self, binding: WorktreeBinding) -> bool:
        """Log unbinding attempt and allow all unbindings."""
        print(f"[Worktree] Unbinding from {binding.repo_id}/{binding.worktree_id}")
        return True

    def after_unbind(self, former_binding: WorktreeBinding) -> None:
        """Log successful unbinding."""
        print(f"[Worktree] Successfully unbound from {former_binding.repo_id}/{former_binding.worktree_id}")

    def on_bind_error(self, repo_id: str, worktree_id: str, error: Exception) -> None:
        """Log binding errors."""
        print(f"[Worktree] Failed to bind to {repo_id}/{worktree_id}: {error}")


class RestrictiveWorktreePolicy:
    """Example policy that demonstrates restrictive binding rules.
    
    This shows how specialized implementations might enforce business
    rules around worktree binding. Use this as a template for creating
    policies that match your organization's requirements.
    """

    def __init__(self, *, allow_rebinding: bool = False, allowed_repos: Optional[set[str]] = None):
        """Initialize restrictive policy.
        
        Args:
            allow_rebinding: Whether to allow switching between worktrees
            allowed_repos: Set of repository IDs that are allowed for binding
        """
        self.allow_rebinding = allow_rebinding
        self.allowed_repos = allowed_repos or set()

    def before_bind(self, repo_id: str, worktree_id: str, current_binding: Optional[WorktreeBinding]) -> bool:
        """Validate binding request against policy rules."""
        # Check if repo is allowed
        if self.allowed_repos and repo_id not in self.allowed_repos:
            print(f"[Worktree] Rejected binding to {repo_id}: not in allowed repos")
            return False
        
        # Check rebinding policy
        if current_binding and not self.allow_rebinding:
            print(f"[Worktree] Rejected rebinding from {current_binding.repo_id} to {repo_id}: rebinding disabled")
            return False
        
        # Basic validation
        if not repo_id or not worktree_id:
            print(f"[Worktree] Rejected binding: empty repo_id or worktree_id")
            return False
            
        return True

    def after_bind(self, binding: WorktreeBinding) -> None:
        """Log successful binding."""
        print(f"[Worktree] Policy allowed binding to {binding.repo_id}/{binding.worktree_id}")

    def before_unbind(self, binding: WorktreeBinding) -> bool:
        """Always allow unbinding in this example policy."""
        return True

    def after_unbind(self, former_binding: WorktreeBinding) -> None:
        """Log successful unbinding."""
        print(f"[Worktree] Policy allowed unbinding from {former_binding.repo_id}/{former_binding.worktree_id}")

    def on_bind_error(self, repo_id: str, worktree_id: str, error: Exception) -> None:
        """Log binding errors."""
        print(f"[Worktree] Policy error for {repo_id}/{worktree_id}: {error}")


class NoOpWorktreePolicy:
    """Example no-operation policy that allows all operations silently.
    
    This demonstrates the minimal policy implementation that simply
    allows all operations without any additional behavior.
    """

    def before_bind(self, repo_id: str, worktree_id: str, current_binding: Optional[WorktreeBinding]) -> bool:
        """Allow all bindings."""
        return True

    def after_bind(self, binding: WorktreeBinding) -> None:
        """No action on successful binding."""
        pass

    def before_unbind(self, binding: WorktreeBinding) -> bool:
        """Allow all unbindings."""
        return True

    def after_unbind(self, former_binding: WorktreeBinding) -> None:
        """No action on successful unbinding."""
        pass

    def on_bind_error(self, repo_id: str, worktree_id: str, error: Exception) -> None:
        """No action on binding errors."""
        pass