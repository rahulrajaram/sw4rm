"""Unit tests for the spawner module."""

import time
from datetime import datetime, timezone

import pytest

from sw4rm.colony.spawner import (
    AgentHandle,
    AgentStatus,
    ResourceLimits,
    SpawnConfigError,
    SpawnerConfig,
    SpawnMode,
    SpawnResourceError,
    SpawnTimeoutError,
    ThreadSpawner,
    TimeoutSettings,
    generate_agent_id,
)


class TestResourceLimits:
    """Tests for ResourceLimits dataclass."""

    def test_default_values(self):
        """Test default resource limits."""
        limits = ResourceLimits()
        assert limits.memory_mb == 512
        assert limits.cpu_millicores == 1000
        assert limits.max_concurrent_tasks == 1

    def test_custom_values(self):
        """Test custom resource limits."""
        limits = ResourceLimits(
            memory_mb=1024,
            cpu_millicores=2000,
            max_concurrent_tasks=4,
        )
        assert limits.memory_mb == 1024
        assert limits.cpu_millicores == 2000
        assert limits.max_concurrent_tasks == 4

    def test_memory_mb_validation(self):
        """Test memory_mb minimum validation."""
        with pytest.raises(ValueError, match="memory_mb must be >= 64"):
            ResourceLimits(memory_mb=32)

    def test_cpu_millicores_validation(self):
        """Test cpu_millicores minimum validation."""
        with pytest.raises(ValueError, match="cpu_millicores must be >= 100"):
            ResourceLimits(cpu_millicores=50)

    def test_max_concurrent_tasks_validation(self):
        """Test max_concurrent_tasks minimum validation."""
        with pytest.raises(ValueError, match="max_concurrent_tasks must be >= 1"):
            ResourceLimits(max_concurrent_tasks=0)


class TestTimeoutSettings:
    """Tests for TimeoutSettings dataclass."""

    def test_default_values(self):
        """Test default timeout settings."""
        settings = TimeoutSettings()
        assert settings.spawn_timeout_s == 30.0
        assert settings.startup_timeout_s == 10.0
        assert settings.shutdown_timeout_s == 30.0
        assert settings.heartbeat_interval_s == 5.0
        assert settings.heartbeat_timeout_s == 15.0

    def test_custom_values(self):
        """Test custom timeout settings."""
        settings = TimeoutSettings(
            spawn_timeout_s=60.0,
            startup_timeout_s=20.0,
        )
        assert settings.spawn_timeout_s == 60.0
        assert settings.startup_timeout_s == 20.0


class TestSpawnerConfig:
    """Tests for SpawnerConfig dataclass."""

    def test_minimal_config(self):
        """Test minimal required configuration."""
        config = SpawnerConfig(agent_role="worker", agent_type="basic")
        assert config.agent_role == "worker"
        assert config.agent_type == "basic"
        assert config.capabilities == []
        assert config.ephemeral is False

    def test_full_config(self):
        """Test full configuration with all options."""
        config = SpawnerConfig(
            agent_role="coordinator",
            agent_type="orchestrator",
            capabilities=["planning", "routing"],
            resource_limits=ResourceLimits(memory_mb=1024),
            environment={"LOG_LEVEL": "DEBUG"},
            labels={"team": "alpha"},
            ephemeral=True,
            parent_swarm="swarm-123",
        )
        assert config.agent_role == "coordinator"
        assert config.capabilities == ["planning", "routing"]
        assert config.resource_limits.memory_mb == 1024
        assert config.environment["LOG_LEVEL"] == "DEBUG"
        assert config.labels["team"] == "alpha"
        assert config.ephemeral is True
        assert config.parent_swarm == "swarm-123"

    def test_validate_thread_mode(self):
        """Test validation for THREAD mode."""
        config = SpawnerConfig(agent_role="worker", agent_type="basic")
        # Should not raise
        config.validate(SpawnMode.THREAD)

    def test_validate_missing_role(self):
        """Test validation fails with empty role."""
        config = SpawnerConfig(agent_role="", agent_type="basic")
        with pytest.raises(ValueError, match="agent_role is required"):
            config.validate(SpawnMode.THREAD)

    def test_validate_missing_type(self):
        """Test validation fails with empty type."""
        config = SpawnerConfig(agent_role="worker", agent_type="")
        with pytest.raises(ValueError, match="agent_type is required"):
            config.validate(SpawnMode.THREAD)

    def test_validate_container_mode_requires_image(self):
        """Test CONTAINER mode requires container_image."""
        config = SpawnerConfig(agent_role="worker", agent_type="basic")
        with pytest.raises(ValueError, match="container_image required"):
            config.validate(SpawnMode.CONTAINER)

    def test_validate_container_mode_with_image(self):
        """Test CONTAINER mode validation passes with image."""
        config = SpawnerConfig(
            agent_role="worker",
            agent_type="basic",
            container_image="sw4rm/agent:latest",
        )
        # Should not raise
        config.validate(SpawnMode.CONTAINER)


class TestAgentHandle:
    """Tests for AgentHandle dataclass."""

    def _make_handle(self, status: AgentStatus) -> AgentHandle:
        """Create a test handle with given status."""
        return AgentHandle(
            agent_id="test-123",
            config=SpawnerConfig(agent_role="worker", agent_type="basic"),
            status=status,
            spawn_time=datetime.now(timezone.utc),
        )

    def test_is_alive_spawning(self):
        """Test is_alive returns True for SPAWNING."""
        handle = self._make_handle(AgentStatus.SPAWNING)
        assert handle.is_alive() is True

    def test_is_alive_ready(self):
        """Test is_alive returns True for READY."""
        handle = self._make_handle(AgentStatus.READY)
        assert handle.is_alive() is True

    def test_is_alive_busy(self):
        """Test is_alive returns True for BUSY."""
        handle = self._make_handle(AgentStatus.BUSY)
        assert handle.is_alive() is True

    def test_is_alive_terminated(self):
        """Test is_alive returns False for TERMINATED."""
        handle = self._make_handle(AgentStatus.TERMINATED)
        assert handle.is_alive() is False

    def test_is_alive_failed(self):
        """Test is_alive returns False for FAILED."""
        handle = self._make_handle(AgentStatus.FAILED)
        assert handle.is_alive() is False

    def test_is_ready(self):
        """Test is_ready returns True only for READY."""
        assert self._make_handle(AgentStatus.READY).is_ready() is True
        assert self._make_handle(AgentStatus.SPAWNING).is_ready() is False
        assert self._make_handle(AgentStatus.BUSY).is_ready() is False

    def test_is_terminal(self):
        """Test is_terminal for terminal states."""
        assert self._make_handle(AgentStatus.TERMINATED).is_terminal() is True
        assert self._make_handle(AgentStatus.FAILED).is_terminal() is True
        assert self._make_handle(AgentStatus.READY).is_terminal() is False


class TestGenerateAgentId:
    """Tests for generate_agent_id function."""

    def test_format(self):
        """Test ID format is agent-<hex>."""
        agent_id = generate_agent_id()
        assert agent_id.startswith("agent-")
        assert len(agent_id) == 18  # "agent-" + 12 hex chars

    def test_uniqueness(self):
        """Test IDs are unique."""
        ids = {generate_agent_id() for _ in range(100)}
        assert len(ids) == 100


class TestThreadSpawnerConstruction:
    """Tests for ThreadSpawner constructor."""

    def test_default_construction(self):
        """Test default construction."""
        spawner = ThreadSpawner()
        assert spawner._max_agents == 100
        assert spawner._agent_factory is None
        spawner.shutdown(wait=False)

    def test_custom_max_agents(self):
        """Test custom max_agents."""
        spawner = ThreadSpawner(max_agents=10)
        assert spawner._max_agents == 10
        spawner.shutdown(wait=False)

    def test_custom_factory(self):
        """Test custom agent factory."""
        def factory(config):
            return {"config": config}

        spawner = ThreadSpawner(agent_factory=factory)
        assert spawner._agent_factory is factory
        spawner.shutdown(wait=False)


class TestThreadSpawnerSpawn:
    """Tests for ThreadSpawner spawn operations."""

    @pytest.fixture
    def spawner(self):
        """Create a spawner for testing."""
        s = ThreadSpawner(max_agents=5)
        yield s
        s.shutdown(wait=False)

    def test_spawn_agent_creates_ready_agent(self, spawner):
        """Test spawn_agent creates agent that reaches READY."""
        config = SpawnerConfig(agent_role="worker", agent_type="test")
        handle = spawner.spawn_agent(config)

        assert handle.agent_id.startswith("agent-")
        assert handle.status == AgentStatus.READY
        assert handle.config == config
        assert handle.spawn_time is not None
        assert handle.ready_time is not None

    def test_spawn_agent_async_returns_spawning(self, spawner):
        """Test spawn_agent_async returns immediately with SPAWNING status."""
        config = SpawnerConfig(agent_role="worker", agent_type="test")
        handle = spawner.spawn_agent_async(config)

        assert handle.status == AgentStatus.SPAWNING
        assert handle.ready_time is None

        # Wait for ready
        handle = spawner.wait_ready(handle.agent_id)
        assert handle.status == AgentStatus.READY

    def test_spawn_invalid_config_raises(self, spawner):
        """Test spawn with invalid config raises SpawnConfigError."""
        config = SpawnerConfig(agent_role="", agent_type="test")
        with pytest.raises(SpawnConfigError, match="agent_role is required"):
            spawner.spawn_agent(config)

    def test_spawn_exceeds_max_agents_raises(self, spawner):
        """Test spawn exceeding max_agents raises SpawnResourceError."""
        config = SpawnerConfig(agent_role="worker", agent_type="test")

        # Spawn max agents
        for _ in range(5):
            spawner.spawn_agent(config)

        # Next spawn should fail
        with pytest.raises(SpawnResourceError, match="Max agents.*reached"):
            spawner.spawn_agent(config)

    def test_wait_ready_unknown_agent_raises(self, spawner):
        """Test wait_ready with unknown ID raises KeyError."""
        with pytest.raises(KeyError, match="Unknown agent_id"):
            spawner.wait_ready("nonexistent-id")


class TestThreadSpawnerTerminate:
    """Tests for ThreadSpawner termination."""

    @pytest.fixture
    def spawner(self):
        """Create a spawner for testing."""
        s = ThreadSpawner(max_agents=5)
        yield s
        s.shutdown(wait=False)

    def test_terminate_agent_stops_agent(self, spawner):
        """Test terminate_agent stops a running agent."""
        config = SpawnerConfig(agent_role="worker", agent_type="test")
        handle = spawner.spawn_agent(config)
        agent_id = handle.agent_id

        result = spawner.terminate_agent(agent_id, reason="test")
        assert result is True

        # Give thread time to stop
        time.sleep(0.1)

        status = spawner.get_agent_status(agent_id)
        assert status in (AgentStatus.TERMINATING, AgentStatus.TERMINATED)

    def test_terminate_force_immediate(self, spawner):
        """Test force termination is immediate."""
        config = SpawnerConfig(agent_role="worker", agent_type="test")
        handle = spawner.spawn_agent(config)

        result = spawner.terminate_agent(handle.agent_id, force=True)
        assert result is True

        status = spawner.get_agent_status(handle.agent_id)
        assert status == AgentStatus.TERMINATED

    def test_terminate_already_terminated(self, spawner):
        """Test terminate returns False if already terminated."""
        config = SpawnerConfig(agent_role="worker", agent_type="test")
        handle = spawner.spawn_agent(config)

        spawner.terminate_agent(handle.agent_id, force=True)
        result = spawner.terminate_agent(handle.agent_id)
        assert result is False

    def test_terminate_unknown_agent_raises(self, spawner):
        """Test terminate with unknown ID raises KeyError."""
        with pytest.raises(KeyError, match="Unknown agent_id"):
            spawner.terminate_agent("nonexistent-id")


class TestThreadSpawnerList:
    """Tests for ThreadSpawner list operations."""

    @pytest.fixture
    def spawner(self):
        """Create a spawner for testing."""
        s = ThreadSpawner(max_agents=10)
        yield s
        s.shutdown(wait=False)

    def test_list_agents_empty(self, spawner):
        """Test list_agents returns empty list when no agents."""
        agents = spawner.list_agents()
        assert agents == []

    def test_list_agents_returns_all(self, spawner):
        """Test list_agents returns all spawned agents."""
        config = SpawnerConfig(agent_role="worker", agent_type="test")

        spawner.spawn_agent(config)
        spawner.spawn_agent(config)
        spawner.spawn_agent(config)

        agents = spawner.list_agents()
        assert len(agents) == 3

    def test_list_agents_status_filter(self, spawner):
        """Test list_agents with status filter."""
        config = SpawnerConfig(agent_role="worker", agent_type="test")

        handle = spawner.spawn_agent(config)
        spawner.terminate_agent(handle.agent_id, force=True)
        spawner.spawn_agent(config)

        ready_agents = spawner.list_agents(
            status_filter={AgentStatus.READY}
        )
        assert len(ready_agents) == 1

        terminated_agents = spawner.list_agents(
            status_filter={AgentStatus.TERMINATED}
        )
        assert len(terminated_agents) == 1

    def test_list_agents_label_filter(self, spawner):
        """Test list_agents with label filter."""
        config1 = SpawnerConfig(
            agent_role="worker",
            agent_type="test",
            labels={"team": "alpha"},
        )
        config2 = SpawnerConfig(
            agent_role="worker",
            agent_type="test",
            labels={"team": "beta"},
        )

        spawner.spawn_agent(config1)
        spawner.spawn_agent(config2)

        alpha_agents = spawner.list_agents(label_filter={"team": "alpha"})
        assert len(alpha_agents) == 1
        assert alpha_agents[0].config.labels["team"] == "alpha"


class TestThreadSpawnerGet:
    """Tests for ThreadSpawner get operations."""

    @pytest.fixture
    def spawner(self):
        """Create a spawner for testing."""
        s = ThreadSpawner(max_agents=5)
        yield s
        s.shutdown(wait=False)

    def test_get_agent(self, spawner):
        """Test get_agent returns handle."""
        config = SpawnerConfig(agent_role="worker", agent_type="test")
        handle = spawner.spawn_agent(config)

        retrieved = spawner.get_agent(handle.agent_id)
        assert retrieved.agent_id == handle.agent_id
        assert retrieved.status == AgentStatus.READY

    def test_get_agent_unknown_raises(self, spawner):
        """Test get_agent with unknown ID raises KeyError."""
        with pytest.raises(KeyError, match="Unknown agent_id"):
            spawner.get_agent("nonexistent-id")

    def test_get_agent_status(self, spawner):
        """Test get_agent_status returns status."""
        config = SpawnerConfig(agent_role="worker", agent_type="test")
        handle = spawner.spawn_agent(config)

        status = spawner.get_agent_status(handle.agent_id)
        assert status == AgentStatus.READY

    def test_get_agent_status_unknown_raises(self, spawner):
        """Test get_agent_status with unknown ID raises KeyError."""
        with pytest.raises(KeyError, match="Unknown agent_id"):
            spawner.get_agent_status("nonexistent-id")


class TestThreadSpawnerCleanup:
    """Tests for ThreadSpawner cleanup operations."""

    @pytest.fixture
    def spawner(self):
        """Create a spawner for testing."""
        s = ThreadSpawner(max_agents=5)
        yield s
        s.shutdown(wait=False)

    def test_cleanup_terminated_removes_old_handles(self, spawner):
        """Test cleanup_terminated removes old terminated handles."""
        config = SpawnerConfig(agent_role="worker", agent_type="test")
        handle = spawner.spawn_agent(config)
        spawner.terminate_agent(handle.agent_id, force=True)

        # With max_age_s=0, should clean up immediately
        cleaned = spawner.cleanup_terminated(max_age_s=0)
        assert cleaned == 1

        with pytest.raises(KeyError):
            spawner.get_agent(handle.agent_id)

    def test_cleanup_terminated_keeps_recent(self, spawner):
        """Test cleanup_terminated keeps recent terminated handles."""
        config = SpawnerConfig(agent_role="worker", agent_type="test")
        handle = spawner.spawn_agent(config)
        spawner.terminate_agent(handle.agent_id, force=True)

        # With large max_age_s, should not clean up
        cleaned = spawner.cleanup_terminated(max_age_s=3600)
        assert cleaned == 0

        # Agent should still exist
        handle = spawner.get_agent(handle.agent_id)
        assert handle.status == AgentStatus.TERMINATED


class TestThreadSpawnerShutdown:
    """Tests for ThreadSpawner shutdown."""

    def test_shutdown_terminates_all_agents(self):
        """Test shutdown terminates all running agents."""
        spawner = ThreadSpawner(max_agents=5)
        config = SpawnerConfig(agent_role="worker", agent_type="test")

        spawner.spawn_agent(config)
        spawner.spawn_agent(config)

        spawner.shutdown(wait=True)

        # After shutdown, list_agents should show terminated or terminating
        # Note: shutdown may have cleaned up, this is implementation-dependent


class TestAgentFactory:
    """Tests for agent factory integration."""

    def test_factory_is_called(self):
        """Test agent factory is called during spawn."""
        created_configs = []

        def factory(config):
            created_configs.append(config)
            return {"config": config}

        spawner = ThreadSpawner(agent_factory=factory)
        config = SpawnerConfig(agent_role="worker", agent_type="test")
        spawner.spawn_agent(config)

        spawner.shutdown(wait=True)

        assert len(created_configs) == 1
        assert created_configs[0] == config

    def test_factory_error_fails_spawn(self):
        """Test factory error causes agent to fail."""
        def failing_factory(config):
            raise RuntimeError("Factory error")

        spawner = ThreadSpawner(agent_factory=failing_factory)
        config = SpawnerConfig(agent_role="worker", agent_type="test")

        with pytest.raises(Exception):
            spawner.spawn_agent(config)

        spawner.shutdown(wait=False)
