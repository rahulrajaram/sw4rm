#!/usr/bin/env python3
"""
Secrets Management Example for SW4RM Protocol.

This example demonstrates:
- Backend selection (auto, file, keyring)
- Storing and retrieving scoped and global secrets
- Resolver precedence: explicit > env > scoped > global
- Error handling for missing secrets
- Listing all secrets

Prerequisites:
  - Install deps: `python -m pip install -e ".[dev]"`

Run:
  python examples/secrets_example.py
"""
from __future__ import annotations

import tempfile
from pathlib import Path

from sw4rm.secrets import (
    Scope,
    SecretKey,
    SecretNotFound,
    SecretValue,
    Secrets,
)
from sw4rm.secrets.backends.file_backend import FileBackend
from sw4rm.secrets.resolver import Resolver


def demo_backend_selection():
    """Demonstrate backend selection modes."""
    print("\n" + "=" * 60)
    print("SCENARIO 1: Backend Selection")
    print("=" * 60)

    from sw4rm.secrets.factory import select_backend

    # File backend (always available)
    _, name = select_backend("file")
    print(f"\n  Explicit file backend: {name}")

    # Auto selection (prefers keyring, falls back to file)
    _, name_auto = select_backend("auto")
    print(f"  Auto-selected backend: {name_auto}")

    print("\n  Backend modes: auto, file, keyring")
    print("  Env override: SW4RM_SECRETS_BACKEND=file")


def demo_store_and_retrieve():
    """Demonstrate storing and retrieving secrets with scopes."""
    print("\n" + "=" * 60)
    print("SCENARIO 2: Store and Retrieve Secrets")
    print("=" * 60)

    with tempfile.TemporaryDirectory() as tmpdir:
        backend = FileBackend(path=Path(tmpdir) / "secrets.json")
        store = Secrets(backend)

        # Global scope (shared across all agents)
        global_scope = Scope(None)
        # Agent-specific scope
        agent_scope = Scope("agent-alpha")

        # Store global API key
        store.set(global_scope, SecretKey("api_key"), SecretValue("sk-global-abc123"))
        print("\n  Stored global secret: api_key")

        # Store agent-scoped override
        store.set(agent_scope, SecretKey("api_key"), SecretValue("sk-agent-xyz789"))
        print("  Stored scoped secret: agent-alpha/api_key")

        # Store agent-specific secret
        store.set(agent_scope, SecretKey("db_password"), SecretValue("pg-secret-42"))
        print("  Stored scoped secret: agent-alpha/db_password")

        # Retrieve global
        val = store.get(global_scope, SecretKey("api_key"))
        print(f"\n  Global api_key: {val}")

        # Retrieve scoped (overrides global)
        val_scoped = store.get(agent_scope, SecretKey("api_key"))
        print(f"  Scoped api_key: {val_scoped}")

        # Retrieve agent-only secret
        val_db = store.get(agent_scope, SecretKey("db_password"))
        print(f"  Scoped db_password: {val_db}")


def demo_resolver_precedence():
    """Demonstrate the four-level resolver precedence."""
    print("\n" + "=" * 60)
    print("SCENARIO 3: Resolver Precedence")
    print("=" * 60)

    with tempfile.TemporaryDirectory() as tmpdir:
        backend = FileBackend(path=Path(tmpdir) / "secrets.json")
        store = Secrets(backend)

        global_scope = Scope(None)
        agent_scope = Scope("agent-beta")

        # Seed the store
        store.set(global_scope, SecretKey("token"), SecretValue("global-token"))
        store.set(agent_scope, SecretKey("token"), SecretValue("scoped-token"))

        # Use a controlled env dict (not real os.environ)
        fake_env = {"SW4RM_TOKEN": "env-token"}
        resolver = Resolver(backend, env=fake_env)

        key = SecretKey("token")

        # Level 1: Explicit wins over everything
        val, src = resolver.resolve(key, agent_scope, explicit="cli-token", env_var="SW4RM_TOKEN")
        print(f"\n  1. Explicit provided:  value={val}, source={src.value}")

        # Level 2: Env var (no explicit)
        val, src = resolver.resolve(key, agent_scope, env_var="SW4RM_TOKEN")
        print(f"  2. Env var fallback:   value={val}, source={src.value}")

        # Level 3: Scoped secret (no explicit, no env var)
        val, src = resolver.resolve(key, agent_scope)
        print(f"  3. Scoped fallback:    value={val}, source={src.value}")

        # Level 4: Global secret (scope has no override)
        other_scope = Scope("agent-gamma")
        val, src = resolver.resolve(key, other_scope)
        print(f"  4. Global fallback:    value={val}, source={src.value}")

        print("\n  Precedence: explicit > env > scoped > global")


def demo_error_handling():
    """Demonstrate error handling for missing secrets."""
    print("\n" + "=" * 60)
    print("SCENARIO 4: Error Handling")
    print("=" * 60)

    with tempfile.TemporaryDirectory() as tmpdir:
        backend = FileBackend(path=Path(tmpdir) / "secrets.json")
        store = Secrets(backend)

        # Try to get a secret that doesn't exist
        try:
            store.get(Scope(None), SecretKey("nonexistent"))
        except SecretNotFound as e:
            print(f"\n  SecretNotFound: {e}")

        # Try resolver with no fallback
        resolver = Resolver(backend, env={})
        try:
            resolver.resolve(SecretKey("missing"), Scope("test"))
        except SecretNotFound as e:
            print(f"  Resolver SecretNotFound: {e}")

        print("\n  Missing secrets raise SecretNotFound with scope and key info")


def demo_listing():
    """Demonstrate listing all stored secrets."""
    print("\n" + "=" * 60)
    print("SCENARIO 5: Listing Secrets")
    print("=" * 60)

    with tempfile.TemporaryDirectory() as tmpdir:
        backend = FileBackend(path=Path(tmpdir) / "secrets.json")
        store = Secrets(backend)

        # Store a few secrets
        store.set(Scope(None), SecretKey("global_a"), SecretValue("val_a"))
        store.set(Scope(None), SecretKey("global_b"), SecretValue("val_b"))
        store.set(Scope("team-x"), SecretKey("team_secret"), SecretValue("val_c"))
        store.set(Scope("team-y"), SecretKey("team_secret"), SecretValue("val_d"))

        # List all
        all_secrets = store.list()
        print(f"\n  Total secrets stored: {len(all_secrets)}")
        for (scope_name, key), value in sorted(
            all_secrets.items(), key=lambda x: (x[0][0] or "", x[0][1])
        ):
            scope_label = scope_name or "(global)"
            print(f"    {scope_label:15s} / {key:15s} = {value}")

        # List by scope
        global_only = store.list(Scope(None))
        print(f"\n  Global scope only: {len(global_only)} secret(s)")

        team_x = store.list(Scope("team-x"))
        print(f"  team-x scope only: {len(team_x)} secret(s)")


def main() -> int:
    """Run all secrets management examples."""
    print("\nSW4RM Secrets Management Example")
    print("=" * 60)
    print("This demonstrates scoped secret storage, resolution, and listing\n")

    demo_backend_selection()
    demo_store_and_retrieve()
    demo_resolver_precedence()
    demo_error_handling()
    demo_listing()

    print("\n" + "=" * 60)
    print("ALL SECRETS SCENARIOS COMPLETED")
    print("=" * 60)
    print("\nKey takeaways:")
    print("1. Use select_backend() for auto/file/keyring selection")
    print("2. Scope(None) = global, Scope('name') = agent-specific")
    print("3. Resolver follows: explicit > env > scoped > global")
    print("4. SecretNotFound raised when no fallback exists")
    print("5. list() returns all secrets, optionally filtered by scope")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
