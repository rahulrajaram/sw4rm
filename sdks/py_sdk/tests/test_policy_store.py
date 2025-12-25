"""Tests for policy storage and retrieval."""

import json
import tempfile
from pathlib import Path

import pytest

from sw4rm.policy_store import (
    InMemoryPolicyStore,
    JSONFilePolicyStore,
    generate_policy_version,
)
from sw4rm.policy_types import (
    EffectivePolicy,
    NegotiationPolicy,
    ExecutionPolicy,
    EscalationPolicy,
)


class TestPolicyVersionGeneration:
    """Tests for policy version generation."""

    def test_generate_version_format(self):
        """Test that generated versions have the expected format."""
        version = generate_policy_version()

        # Should be in format: {timestamp_ms}_{uuid}
        # The UUID contains hyphens, not underscores, so split on _ gives 2 parts
        parts = version.split("_", 1)
        assert len(parts) == 2

        # First part should be numeric (timestamp)
        assert parts[0].isdigit()

        # Second part should be a valid UUID (contains hyphens)
        assert "-" in parts[1]

    def test_generate_version_uniqueness(self):
        """Test that generated versions are unique."""
        versions = {generate_policy_version() for _ in range(100)}
        assert len(versions) == 100  # All unique


class TestInMemoryPolicyStore:
    """Tests for in-memory policy storage."""

    def test_save_and_get_policy(self):
        """Test basic save and retrieve operations."""
        store = InMemoryPolicyStore()

        policy = EffectivePolicy(
            policy_id="test_policy_1",
            version="1.0",
            negotiation=NegotiationPolicy(max_rounds=5),
        )

        policy_id = store.save_policy(policy)
        assert policy_id == "test_policy_1"

        retrieved = store.get_policy("test_policy_1")
        assert retrieved.policy_id == "test_policy_1"
        assert retrieved.negotiation.max_rounds == 5

    def test_save_without_policy_id(self):
        """Test that policies without IDs get auto-generated IDs."""
        store = InMemoryPolicyStore()

        policy = EffectivePolicy(
            negotiation=NegotiationPolicy(max_rounds=5),
        )

        policy_id = store.save_policy(policy)
        assert policy_id.startswith("policy_")

        retrieved = store.get_policy(policy_id)
        assert retrieved.policy_id == policy_id

    def test_save_auto_generates_version(self):
        """Test that versions are auto-generated when not set or default."""
        store = InMemoryPolicyStore()

        # Test with default version "1.0"
        policy = EffectivePolicy(
            policy_id="test_policy_1",
            version="1.0",
        )

        store.save_policy(policy)
        retrieved = store.get_policy("test_policy_1")

        # Version should be updated to timestamp_uuid format
        assert retrieved.version != "1.0"
        assert "_" in retrieved.version

    def test_get_nonexistent_policy(self):
        """Test that getting a nonexistent policy raises KeyError."""
        store = InMemoryPolicyStore()

        with pytest.raises(KeyError, match="Policy not found: nonexistent"):
            store.get_policy("nonexistent")

    def test_list_policies_empty(self):
        """Test listing policies when store is empty."""
        store = InMemoryPolicyStore()
        assert store.list_policies() == []

    def test_list_policies(self):
        """Test listing all policies."""
        store = InMemoryPolicyStore()

        for i in range(3):
            policy = EffectivePolicy(policy_id=f"policy_{i}")
            store.save_policy(policy)

        policies = store.list_policies()
        assert len(policies) == 3
        assert policies == ["policy_0", "policy_1", "policy_2"]  # Sorted

    def test_list_policies_with_prefix(self):
        """Test listing policies with a prefix filter."""
        store = InMemoryPolicyStore()

        store.save_policy(EffectivePolicy(policy_id="prod_policy_1"))
        store.save_policy(EffectivePolicy(policy_id="prod_policy_2"))
        store.save_policy(EffectivePolicy(policy_id="dev_policy_1"))

        prod_policies = store.list_policies(prefix="prod_")
        assert len(prod_policies) == 2
        assert prod_policies == ["prod_policy_1", "prod_policy_2"]

        dev_policies = store.list_policies(prefix="dev_")
        assert len(dev_policies) == 1
        assert dev_policies == ["dev_policy_1"]

    def test_policy_history(self):
        """Test that policy history tracks all versions."""
        store = InMemoryPolicyStore()

        # Save three versions of the same policy
        for max_rounds in [5, 10, 15]:
            policy = EffectivePolicy(
                policy_id="test_policy",
                negotiation=NegotiationPolicy(max_rounds=max_rounds),
            )
            store.save_policy(policy)

        history = store.get_policy_history("test_policy")
        assert len(history) == 3

        # Check that versions are in chronological order
        assert history[0].negotiation.max_rounds == 5
        assert history[1].negotiation.max_rounds == 10
        assert history[2].negotiation.max_rounds == 15

        # Latest version should match get_policy
        latest = store.get_policy("test_policy")
        assert latest.negotiation.max_rounds == 15

    def test_policy_history_nonexistent(self):
        """Test that getting history for nonexistent policy raises KeyError."""
        store = InMemoryPolicyStore()

        with pytest.raises(KeyError, match="Policy not found: nonexistent"):
            store.get_policy_history("nonexistent")

    def test_policy_immutability(self):
        """Test that stored policies are immutable (deep copied)."""
        store = InMemoryPolicyStore()

        policy = EffectivePolicy(
            policy_id="test_policy",
            negotiation=NegotiationPolicy(max_rounds=5),
        )

        store.save_policy(policy)

        # Modify the original
        policy.negotiation.max_rounds = 100

        # Retrieved policy should not be affected
        retrieved = store.get_policy("test_policy")
        assert retrieved.negotiation.max_rounds != 100

    def test_complex_policy_storage(self):
        """Test storing and retrieving complex policies with all fields."""
        store = InMemoryPolicyStore()

        policy = EffectivePolicy(
            policy_id="complex_policy",
            version="1.0",
            negotiation=NegotiationPolicy(
                max_rounds=10,
                score_threshold=0.85,
                diff_tolerance=0.15,
                round_timeout_ms=45000,
                token_budget_per_round=5000,
                total_token_budget=50000,
                oscillation_limit=5,
                hitl_mode="PauseBetweenRounds",
            ),
            execution=ExecutionPolicy(
                timeout_ms=120000,
                max_retries=5,
                backoff="linear",
                worktree_required=True,
                network_policy="full",
                privilege_level="elevated",
                budget_cpu_ms=60000,
                budget_wall_ms=120000,
            ),
            escalation=EscalationPolicy(
                auto_escalate_on_deadlock=False,
                deadlock_rounds=5,
                escalation_reasons=["timeout", "budget_exceeded"],
            ),
        )

        store.save_policy(policy)
        retrieved = store.get_policy("complex_policy")

        # Verify all fields are preserved
        assert retrieved.negotiation.max_rounds == 10
        assert retrieved.negotiation.score_threshold == 0.85
        assert retrieved.negotiation.hitl_mode == "PauseBetweenRounds"
        assert retrieved.execution.worktree_required is True
        assert retrieved.execution.network_policy == "full"
        assert retrieved.escalation.auto_escalate_on_deadlock is False
        assert retrieved.escalation.escalation_reasons == ["timeout", "budget_exceeded"]


class TestJSONFilePolicyStore:
    """Tests for JSON file-based policy storage."""

    def test_save_and_get_policy(self):
        """Test basic save and retrieve operations."""
        with tempfile.TemporaryDirectory() as tmpdir:
            store = JSONFilePolicyStore(tmpdir)

            policy = EffectivePolicy(
                policy_id="test_policy_1",
                version="1.0",
                negotiation=NegotiationPolicy(max_rounds=5),
            )

            policy_id = store.save_policy(policy)
            assert policy_id == "test_policy_1"

            retrieved = store.get_policy("test_policy_1")
            assert retrieved.policy_id == "test_policy_1"
            assert retrieved.negotiation.max_rounds == 5

    def test_persistence_across_instances(self):
        """Test that data persists across store instances."""
        with tempfile.TemporaryDirectory() as tmpdir:
            # Save with first store instance
            store1 = JSONFilePolicyStore(tmpdir)
            policy = EffectivePolicy(
                policy_id="persistent_policy",
                negotiation=NegotiationPolicy(max_rounds=7),
            )
            store1.save_policy(policy)

            # Retrieve with second store instance
            store2 = JSONFilePolicyStore(tmpdir)
            retrieved = store2.get_policy("persistent_policy")
            assert retrieved.negotiation.max_rounds == 7

    def test_storage_directory_creation(self):
        """Test that storage directory is created if it doesn't exist."""
        with tempfile.TemporaryDirectory() as tmpdir:
            nested_dir = Path(tmpdir) / "nested" / "storage"
            store = JSONFilePolicyStore(nested_dir)

            assert nested_dir.exists()
            assert nested_dir.is_dir()

    def test_file_structure(self):
        """Test that JSON files have the correct structure."""
        with tempfile.TemporaryDirectory() as tmpdir:
            store = JSONFilePolicyStore(tmpdir)

            policy = EffectivePolicy(
                policy_id="test_policy",
                negotiation=NegotiationPolicy(max_rounds=5),
            )
            store.save_policy(policy)

            # Read the JSON file directly
            file_path = Path(tmpdir) / "test_policy.json"
            assert file_path.exists()

            with open(file_path, "r", encoding="utf-8") as f:
                data = json.load(f)

            assert "policy_id" in data
            assert "versions" in data
            assert isinstance(data["versions"], list)
            assert len(data["versions"]) == 1

    def test_policy_history(self):
        """Test that policy history is tracked in JSON."""
        with tempfile.TemporaryDirectory() as tmpdir:
            store = JSONFilePolicyStore(tmpdir)

            # Save three versions
            for max_rounds in [5, 10, 15]:
                policy = EffectivePolicy(
                    policy_id="test_policy",
                    negotiation=NegotiationPolicy(max_rounds=max_rounds),
                )
                store.save_policy(policy)

            history = store.get_policy_history("test_policy")
            assert len(history) == 3

            # Verify order
            assert history[0].negotiation.max_rounds == 5
            assert history[1].negotiation.max_rounds == 10
            assert history[2].negotiation.max_rounds == 15

    def test_list_policies(self):
        """Test listing policies from JSON files."""
        with tempfile.TemporaryDirectory() as tmpdir:
            store = JSONFilePolicyStore(tmpdir)

            for i in range(3):
                policy = EffectivePolicy(policy_id=f"policy_{i}")
                store.save_policy(policy)

            policies = store.list_policies()
            assert len(policies) == 3
            assert policies == ["policy_0", "policy_1", "policy_2"]

    def test_list_policies_with_prefix(self):
        """Test listing policies with prefix filter."""
        with tempfile.TemporaryDirectory() as tmpdir:
            store = JSONFilePolicyStore(tmpdir)

            store.save_policy(EffectivePolicy(policy_id="prod_policy_1"))
            store.save_policy(EffectivePolicy(policy_id="prod_policy_2"))
            store.save_policy(EffectivePolicy(policy_id="dev_policy_1"))

            prod_policies = store.list_policies(prefix="prod_")
            assert len(prod_policies) == 2

    def test_get_nonexistent_policy(self):
        """Test that getting a nonexistent policy raises KeyError."""
        with tempfile.TemporaryDirectory() as tmpdir:
            store = JSONFilePolicyStore(tmpdir)

            with pytest.raises(KeyError, match="Policy not found: nonexistent"):
                store.get_policy("nonexistent")

    def test_sanitize_policy_id(self):
        """Test that policy IDs with slashes are sanitized for filesystem."""
        with tempfile.TemporaryDirectory() as tmpdir:
            store = JSONFilePolicyStore(tmpdir)

            # Policy ID with slashes
            policy = EffectivePolicy(
                policy_id="org/team/policy",
                negotiation=NegotiationPolicy(max_rounds=5),
            )

            store.save_policy(policy)

            # Should be retrievable
            retrieved = store.get_policy("org/team/policy")
            assert retrieved.policy_id == "org/team/policy"

            # File should have sanitized name
            sanitized_file = Path(tmpdir) / "org_team_policy.json"
            assert sanitized_file.exists()

    def test_malformed_json_handling(self):
        """Test that malformed JSON files are skipped during list operations."""
        with tempfile.TemporaryDirectory() as tmpdir:
            store = JSONFilePolicyStore(tmpdir)

            # Create a valid policy
            store.save_policy(EffectivePolicy(policy_id="valid_policy"))

            # Create a malformed JSON file
            malformed_file = Path(tmpdir) / "malformed.json"
            with open(malformed_file, "w") as f:
                f.write("{ this is not valid json")

            # list_policies should skip the malformed file
            policies = store.list_policies()
            assert policies == ["valid_policy"]

    def test_complex_policy_roundtrip(self):
        """Test that complex policies survive save/load roundtrip."""
        with tempfile.TemporaryDirectory() as tmpdir:
            store = JSONFilePolicyStore(tmpdir)

            policy = EffectivePolicy(
                policy_id="complex_policy",
                version="1.0",
                negotiation=NegotiationPolicy(
                    max_rounds=10,
                    score_threshold=0.85,
                    diff_tolerance=0.15,
                    round_timeout_ms=45000,
                    token_budget_per_round=5000,
                    total_token_budget=50000,
                    oscillation_limit=5,
                    hitl_mode="PauseBetweenRounds",
                ),
                execution=ExecutionPolicy(
                    timeout_ms=120000,
                    max_retries=5,
                    backoff="linear",
                    worktree_required=True,
                    network_policy="full",
                    privilege_level="elevated",
                ),
                escalation=EscalationPolicy(
                    auto_escalate_on_deadlock=False,
                    deadlock_rounds=5,
                    escalation_reasons=["timeout", "budget_exceeded"],
                ),
            )

            store.save_policy(policy)
            retrieved = store.get_policy("complex_policy")

            # Verify all fields
            assert retrieved.negotiation.max_rounds == 10
            assert retrieved.negotiation.score_threshold == 0.85
            assert retrieved.execution.worktree_required is True
            assert retrieved.escalation.escalation_reasons == ["timeout", "budget_exceeded"]


class TestPolicyStoreComparison:
    """Tests comparing behavior between different store implementations."""

    @pytest.fixture
    def stores(self):
        """Provide both store implementations for comparison testing."""
        tmpdir = tempfile.mkdtemp()
        return {
            "memory": InMemoryPolicyStore(),
            "json": JSONFilePolicyStore(tmpdir),
        }

    def test_consistent_behavior(self, stores):
        """Test that both stores behave consistently."""
        policy = EffectivePolicy(
            policy_id="test_policy",
            negotiation=NegotiationPolicy(max_rounds=8),
        )

        for store_type, store in stores.items():
            policy_id = store.save_policy(policy)
            assert policy_id == "test_policy", f"Failed for {store_type}"

            retrieved = store.get_policy("test_policy")
            assert retrieved.negotiation.max_rounds == 8, f"Failed for {store_type}"

    def test_consistent_listing(self, stores):
        """Test that both stores list policies consistently."""
        for i in range(3):
            policy = EffectivePolicy(policy_id=f"policy_{i}")
            for store in stores.values():
                store.save_policy(policy)

        for store_type, store in stores.items():
            policies = store.list_policies()
            assert len(policies) == 3, f"Failed for {store_type}"
            assert policies == ["policy_0", "policy_1", "policy_2"], f"Failed for {store_type}"

    def test_consistent_history_tracking(self, stores):
        """Test that both stores track history consistently."""
        for max_rounds in [5, 10, 15]:
            policy = EffectivePolicy(
                policy_id="versioned_policy",
                negotiation=NegotiationPolicy(max_rounds=max_rounds),
            )
            for store in stores.values():
                store.save_policy(policy)

        for store_type, store in stores.items():
            history = store.get_policy_history("versioned_policy")
            assert len(history) == 3, f"Failed for {store_type}"
            assert history[0].negotiation.max_rounds == 5, f"Failed for {store_type}"
            assert history[2].negotiation.max_rounds == 15, f"Failed for {store_type}"
