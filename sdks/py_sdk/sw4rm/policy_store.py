"""Policy storage and retrieval abstractions.

This module provides a storage layer for managing EffectivePolicy instances,
supporting both in-memory and persistent storage backends.

Policy snapshots are immutable once stored. Each policy is versioned using
timestamp-based UUIDs to ensure uniqueness and provide chronological ordering.
"""

from __future__ import annotations

import json
import os
import time
import uuid
from abc import ABC, abstractmethod
from pathlib import Path
from typing import Protocol, Optional

from sw4rm.policy_types import EffectivePolicy


def generate_policy_version() -> str:
    """Generate a unique version identifier for a policy.

    Uses a combination of timestamp and UUID to ensure uniqueness
    and provide some chronological ordering.

    Returns:
        A version string in the format: {timestamp_ms}_{uuid}
    """
    timestamp_ms = int(time.time() * 1000)
    unique_id = str(uuid.uuid4())
    return f"{timestamp_ms}_{unique_id}"


class PolicyStore(Protocol):
    """Protocol defining the interface for policy storage backends.

    All policy storage implementations must support these operations.
    Policies are immutable once stored - saving a policy with the same
    policy_id but different version creates a new snapshot in the history.
    """

    def get_policy(self, policy_id: str) -> EffectivePolicy:
        """Retrieve the latest version of a policy by ID.

        Args:
            policy_id: Unique identifier for the policy.

        Returns:
            The most recent version of the policy.

        Raises:
            KeyError: If no policy with the given ID exists.
        """
        ...

    def save_policy(self, policy: EffectivePolicy) -> str:
        """Save a policy snapshot and return its policy_id.

        If the policy has no version set, a new version is generated.
        The policy snapshot is immutable once saved.

        Args:
            policy: The policy to save.

        Returns:
            The policy_id of the saved policy.
        """
        ...

    def list_policies(self, prefix: str = "") -> list[str]:
        """List all policy IDs, optionally filtered by prefix.

        Args:
            prefix: Optional prefix to filter policy IDs.

        Returns:
            List of policy IDs matching the prefix.
        """
        ...

    def get_policy_history(self, policy_id: str) -> list[EffectivePolicy]:
        """Retrieve the complete version history for a policy.

        Returns policies in chronological order (oldest to newest).

        Args:
            policy_id: Unique identifier for the policy.

        Returns:
            List of all versions of the policy.

        Raises:
            KeyError: If no policy with the given ID exists.
        """
        ...


class PolicyStoreABC(ABC):
    """Abstract base class for policy storage backends.

    Provides the same interface as PolicyStore Protocol but as an ABC
    for implementations that prefer inheritance over structural typing.
    """

    @abstractmethod
    def get_policy(self, policy_id: str) -> EffectivePolicy:
        """Retrieve the latest version of a policy by ID."""
        pass

    @abstractmethod
    def save_policy(self, policy: EffectivePolicy) -> str:
        """Save a policy snapshot and return its policy_id."""
        pass

    @abstractmethod
    def list_policies(self, prefix: str = "") -> list[str]:
        """List all policy IDs, optionally filtered by prefix."""
        pass

    @abstractmethod
    def get_policy_history(self, policy_id: str) -> list[EffectivePolicy]:
        """Retrieve the complete version history for a policy."""
        pass


class InMemoryPolicyStore(PolicyStoreABC):
    """In-memory implementation of PolicyStore.

    Stores policies in memory with full version history. Data is lost
    when the process terminates. Suitable for testing and transient usage.

    Thread-safety: This implementation is NOT thread-safe. Use external
    synchronization if accessed from multiple threads.
    """

    def __init__(self) -> None:
        """Initialize an empty in-memory policy store."""
        # Maps policy_id -> list of EffectivePolicy (chronological order)
        self._policies: dict[str, list[EffectivePolicy]] = {}

    def get_policy(self, policy_id: str) -> EffectivePolicy:
        """Retrieve the latest version of a policy by ID.

        Args:
            policy_id: Unique identifier for the policy.

        Returns:
            The most recent version of the policy.

        Raises:
            KeyError: If no policy with the given ID exists.
        """
        if policy_id not in self._policies:
            raise KeyError(f"Policy not found: {policy_id}")
        return self._policies[policy_id][-1]

    def save_policy(self, policy: EffectivePolicy) -> str:
        """Save a policy snapshot and return its policy_id.

        If the policy has no version set or has version "1.0" (default),
        a new version is generated. The policy is deep-copied to ensure
        immutability.

        Args:
            policy: The policy to save.

        Returns:
            The policy_id of the saved policy.
        """
        # Generate version if not set or if using default
        if not policy.version or policy.version == "1.0":
            policy.version = generate_policy_version()

        # Ensure policy_id is set
        if not policy.policy_id:
            policy.policy_id = f"policy_{str(uuid.uuid4())}"

        # Create a snapshot by converting to/from dict (ensures immutability)
        snapshot = EffectivePolicy.from_dict(policy.to_dict())

        # Store in history
        if policy.policy_id not in self._policies:
            self._policies[policy.policy_id] = []
        self._policies[policy.policy_id].append(snapshot)

        return policy.policy_id

    def list_policies(self, prefix: str = "") -> list[str]:
        """List all policy IDs, optionally filtered by prefix.

        Args:
            prefix: Optional prefix to filter policy IDs.

        Returns:
            List of policy IDs matching the prefix, sorted alphabetically.
        """
        if prefix:
            return sorted([pid for pid in self._policies.keys() if pid.startswith(prefix)])
        return sorted(self._policies.keys())

    def get_policy_history(self, policy_id: str) -> list[EffectivePolicy]:
        """Retrieve the complete version history for a policy.

        Returns policies in chronological order (oldest to newest).

        Args:
            policy_id: Unique identifier for the policy.

        Returns:
            List of all versions of the policy.

        Raises:
            KeyError: If no policy with the given ID exists.
        """
        if policy_id not in self._policies:
            raise KeyError(f"Policy not found: {policy_id}")
        return list(self._policies[policy_id])


class JSONFilePolicyStore(PolicyStoreABC):
    """File-based implementation of PolicyStore using JSON.

    Persists policies to disk as JSON files with full version history.
    Each policy is stored in a separate file named {policy_id}.json.

    Storage format:
        {
            "policy_id": "...",
            "versions": [
                {policy dict},
                {policy dict},
                ...
            ]
        }

    Thread-safety: This implementation is NOT thread-safe. Use external
    synchronization if accessed from multiple threads.

    Attributes:
        storage_dir: Directory where policy JSON files are stored.
    """

    def __init__(self, storage_dir: str | Path) -> None:
        """Initialize a JSON file-based policy store.

        Creates the storage directory if it doesn't exist.

        Args:
            storage_dir: Directory to store policy JSON files.
        """
        self.storage_dir = Path(storage_dir)
        self.storage_dir.mkdir(parents=True, exist_ok=True)

    def _get_policy_file(self, policy_id: str) -> Path:
        """Get the file path for a policy ID.

        Args:
            policy_id: The policy identifier.

        Returns:
            Path to the JSON file for this policy.
        """
        # Sanitize policy_id for filesystem safety
        safe_id = policy_id.replace("/", "_").replace("\\", "_")
        return self.storage_dir / f"{safe_id}.json"

    def get_policy(self, policy_id: str) -> EffectivePolicy:
        """Retrieve the latest version of a policy by ID.

        Args:
            policy_id: Unique identifier for the policy.

        Returns:
            The most recent version of the policy.

        Raises:
            KeyError: If no policy with the given ID exists.
        """
        policy_file = self._get_policy_file(policy_id)
        if not policy_file.exists():
            raise KeyError(f"Policy not found: {policy_id}")

        with open(policy_file, "r", encoding="utf-8") as f:
            data = json.load(f)

        versions = data.get("versions", [])
        if not versions:
            raise KeyError(f"Policy has no versions: {policy_id}")

        return EffectivePolicy.from_dict(versions[-1])

    def save_policy(self, policy: EffectivePolicy) -> str:
        """Save a policy snapshot and return its policy_id.

        If the policy has no version set or has version "1.0" (default),
        a new version is generated. The policy is appended to the version
        history in the JSON file.

        Args:
            policy: The policy to save.

        Returns:
            The policy_id of the saved policy.
        """
        # Generate version if not set or if using default
        if not policy.version or policy.version == "1.0":
            policy.version = generate_policy_version()

        # Ensure policy_id is set
        if not policy.policy_id:
            policy.policy_id = f"policy_{str(uuid.uuid4())}"

        policy_file = self._get_policy_file(policy.policy_id)

        # Load existing versions or create new structure
        if policy_file.exists():
            with open(policy_file, "r", encoding="utf-8") as f:
                data = json.load(f)
            versions = data.get("versions", [])
        else:
            versions = []

        # Append new version
        versions.append(policy.to_dict())

        # Write back to file
        data = {
            "policy_id": policy.policy_id,
            "versions": versions
        }

        with open(policy_file, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2, ensure_ascii=False)

        return policy.policy_id

    def list_policies(self, prefix: str = "") -> list[str]:
        """List all policy IDs, optionally filtered by prefix.

        Args:
            prefix: Optional prefix to filter policy IDs.

        Returns:
            List of policy IDs matching the prefix, sorted alphabetically.
        """
        policy_ids = []

        for file_path in self.storage_dir.glob("*.json"):
            # Read policy_id from file
            try:
                with open(file_path, "r", encoding="utf-8") as f:
                    data = json.load(f)
                    policy_id = data.get("policy_id", "")
                    if policy_id and (not prefix or policy_id.startswith(prefix)):
                        policy_ids.append(policy_id)
            except (json.JSONDecodeError, IOError):
                # Skip malformed files
                continue

        return sorted(policy_ids)

    def get_policy_history(self, policy_id: str) -> list[EffectivePolicy]:
        """Retrieve the complete version history for a policy.

        Returns policies in chronological order (oldest to newest).

        Args:
            policy_id: Unique identifier for the policy.

        Returns:
            List of all versions of the policy.

        Raises:
            KeyError: If no policy with the given ID exists.
        """
        policy_file = self._get_policy_file(policy_id)
        if not policy_file.exists():
            raise KeyError(f"Policy not found: {policy_id}")

        with open(policy_file, "r", encoding="utf-8") as f:
            data = json.load(f)

        versions = data.get("versions", [])
        return [EffectivePolicy.from_dict(v) for v in versions]
