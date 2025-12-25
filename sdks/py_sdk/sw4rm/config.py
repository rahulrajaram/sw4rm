from __future__ import annotations

"""SDK configuration primitives.

Provides typed configuration objects and helpers to centralize service
endpoints, agent metadata, and basic runtime knobs. Defaults are sourced from
``sw4rm.constants`` so applications and examples have a single source of truth.

This module supports configuration loading from multiple sources:
- Environment variables (SW4RM_* prefix)
- JSON configuration files
- YAML configuration files (requires PyYAML)
- Programmatic configuration
"""

from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Optional
import json
import logging
import os

from . import constants as C


@dataclass
class Endpoints:
    """Addresses for SW4RM services.

    Only router and registry are required for the reference examples. Additional
    services can be added here as the SDK grows.
    """

    router_addr: str = field(default_factory=C.get_default_router_addr)
    registry_addr: str = field(default_factory=C.get_default_registry_addr)


@dataclass
class RetryPolicy:
    """Simple retry policy for unary calls."""

    max_attempts: int = 3
    initial_backoff_s: float = 0.2
    max_backoff_s: float = 2.0
    backoff_multiplier: float = 2.0


@dataclass
class AgentConfig:
    """Agent runtime configuration.

    - ``agent_id`` and ``name`` identify the agent.
    - ``endpoints`` provides service addresses.
    - ``request_timeout_s`` applies to unary calls unless overridden.
    - ``retry`` controls basic retry for transient failures.
    """

    agent_id: str = "agent-1"
    name: str = "Agent"
    endpoints: Endpoints = field(default_factory=Endpoints)
    request_timeout_s: float = 10.0
    stream_keepalive_s: float = 60.0
    retry: RetryPolicy = field(default_factory=RetryPolicy)
    description: Optional[str] = None


def from_env() -> AgentConfig:
    """Construct ``AgentConfig`` using environment overrides where available.

    Uses ``AGENT_ID`` and ``AGENT_NAME`` if set, and respects the endpoint
    environment variables defined in ``sw4rm.constants``.
    """

    agent_id = os.getenv("AGENT_ID", "agent-1")
    name = os.getenv("AGENT_NAME", "Agent")
    endpoints = Endpoints()  # picks up env via default_factory
    return AgentConfig(agent_id=agent_id, name=name, endpoints=endpoints)


# ---------------------------------------------------------------------------
# Enhanced configuration system (Phase 3.6)
# ---------------------------------------------------------------------------


@dataclass
class SW4RMConfig:
    """Comprehensive SW4RM SDK configuration.

    This configuration object centralizes all SDK settings including service
    endpoints, timeouts, retry policies, observability flags, and feature flags.

    Configuration can be loaded from:
    - Environment variables (SW4RM_* prefix)
    - JSON files
    - YAML files
    - Programmatic defaults

    Attributes:
        router_addr: Address of the router service
        registry_addr: Address of the registry service
        default_timeout_ms: Default timeout for operations in milliseconds
        max_retries: Maximum number of retry attempts for failed operations
        enable_metrics: Whether to collect and export metrics
        enable_tracing: Whether to enable distributed tracing
        log_level: Logging level (DEBUG, INFO, WARNING, ERROR, CRITICAL)
        feature_flags: Dictionary of feature flag name to value mappings
    """

    router_addr: str = field(default_factory=C.get_default_router_addr)
    registry_addr: str = field(default_factory=C.get_default_registry_addr)
    default_timeout_ms: int = 10000
    max_retries: int = 3
    enable_metrics: bool = True
    enable_tracing: bool = True
    log_level: str = "INFO"
    feature_flags: dict[str, Any] = field(default_factory=dict)

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> "SW4RMConfig":
        """Create configuration from a dictionary.

        Args:
            data: Dictionary containing configuration values

        Returns:
            SW4RMConfig instance
        """
        # Extract known fields
        config_data = {}
        for field_name in [
            "router_addr",
            "registry_addr",
            "default_timeout_ms",
            "max_retries",
            "enable_metrics",
            "enable_tracing",
            "log_level",
            "feature_flags",
        ]:
            if field_name in data:
                config_data[field_name] = data[field_name]

        return cls(**config_data)

    def to_dict(self) -> dict[str, Any]:
        """Convert configuration to a dictionary.

        Returns:
            Dictionary representation of the configuration
        """
        return {
            "router_addr": self.router_addr,
            "registry_addr": self.registry_addr,
            "default_timeout_ms": self.default_timeout_ms,
            "max_retries": self.max_retries,
            "enable_metrics": self.enable_metrics,
            "enable_tracing": self.enable_tracing,
            "log_level": self.log_level,
            "feature_flags": self.feature_flags,
        }


def load_config(path: Optional[str] = None) -> SW4RMConfig:
    """Load SW4RM configuration from file or environment.

    Configuration loading order (later sources override earlier ones):
    1. Default values from SW4RMConfig dataclass
    2. Configuration file (if path provided)
    3. Environment variables (SW4RM_* prefix)

    Args:
        path: Optional path to configuration file (JSON or YAML)
              If None, only environment variables are used

    Returns:
        SW4RMConfig instance

    Raises:
        FileNotFoundError: If path is provided but file doesn't exist
        ValueError: If file format is invalid or unsupported

    Example:
        # Load from file and environment
        config = load_config("/etc/sw4rm/config.json")

        # Load from environment only
        config = load_config()

    Environment variables:
        SW4RM_ROUTER_ADDR: Router service address
        SW4RM_REGISTRY_ADDR: Registry service address
        SW4RM_DEFAULT_TIMEOUT_MS: Default timeout in milliseconds
        SW4RM_MAX_RETRIES: Maximum retry attempts
        SW4RM_ENABLE_METRICS: Enable metrics collection (true/false)
        SW4RM_ENABLE_TRACING: Enable tracing (true/false)
        SW4RM_LOG_LEVEL: Log level (DEBUG, INFO, WARNING, ERROR, CRITICAL)
    """
    # Start with defaults
    config_data: dict[str, Any] = {}

    # Load from file if provided
    if path is not None:
        config_path = Path(path)
        if not config_path.exists():
            raise FileNotFoundError(f"Configuration file not found: {path}")

        # Determine file format from extension
        suffix = config_path.suffix.lower()

        if suffix == ".json":
            with open(config_path, "r") as f:
                file_config = json.load(f)
                config_data.update(file_config)

        elif suffix in (".yaml", ".yml"):
            try:
                import yaml
            except ImportError:
                raise ValueError(
                    "YAML support requires PyYAML: pip install pyyaml"
                )

            with open(config_path, "r") as f:
                file_config = yaml.safe_load(f)
                if file_config:
                    config_data.update(file_config)

        else:
            raise ValueError(
                f"Unsupported configuration file format: {suffix}. "
                "Supported formats: .json, .yaml, .yml"
            )

    # Override with environment variables
    env_overrides = _load_from_env()
    config_data.update(env_overrides)

    # Create config object
    return SW4RMConfig.from_dict(config_data)


def _load_from_env() -> dict[str, Any]:
    """Load configuration overrides from environment variables.

    Returns:
        Dictionary of configuration values from environment
    """
    env_config: dict[str, Any] = {}

    # Service addresses
    if "SW4RM_ROUTER_ADDR" in os.environ:
        env_config["router_addr"] = os.environ["SW4RM_ROUTER_ADDR"]

    if "SW4RM_REGISTRY_ADDR" in os.environ:
        env_config["registry_addr"] = os.environ["SW4RM_REGISTRY_ADDR"]

    # Numeric values
    if "SW4RM_DEFAULT_TIMEOUT_MS" in os.environ:
        try:
            env_config["default_timeout_ms"] = int(
                os.environ["SW4RM_DEFAULT_TIMEOUT_MS"]
            )
        except ValueError:
            logging.warning(
                "Invalid SW4RM_DEFAULT_TIMEOUT_MS value, using default"
            )

    if "SW4RM_MAX_RETRIES" in os.environ:
        try:
            env_config["max_retries"] = int(os.environ["SW4RM_MAX_RETRIES"])
        except ValueError:
            logging.warning("Invalid SW4RM_MAX_RETRIES value, using default")

    # Boolean values
    if "SW4RM_ENABLE_METRICS" in os.environ:
        env_config["enable_metrics"] = _parse_bool(
            os.environ["SW4RM_ENABLE_METRICS"]
        )

    if "SW4RM_ENABLE_TRACING" in os.environ:
        env_config["enable_tracing"] = _parse_bool(
            os.environ["SW4RM_ENABLE_TRACING"]
        )

    # Log level
    if "SW4RM_LOG_LEVEL" in os.environ:
        env_config["log_level"] = os.environ["SW4RM_LOG_LEVEL"].upper()

    return env_config


def _parse_bool(value: str) -> bool:
    """Parse a boolean value from string.

    Args:
        value: String value to parse

    Returns:
        Boolean value
    """
    return value.lower() in ("true", "1", "yes", "on")


# Global singleton config instance
_global_config: Optional[SW4RMConfig] = None


def get_config() -> SW4RMConfig:
    """Get the global SW4RM configuration.

    Returns the singleton configuration instance. If no configuration has been
    loaded yet, creates a new one using environment variables.

    Returns:
        Global SW4RMConfig instance

    Example:
        config = get_config()
        print(f"Router: {config.router_addr}")
        print(f"Metrics enabled: {config.enable_metrics}")
    """
    global _global_config

    if _global_config is None:
        # Load default config from environment
        _global_config = load_config()

    return _global_config


def set_config(config: SW4RMConfig) -> None:
    """Set the global SW4RM configuration.

    This allows applications to programmatically configure the SDK
    instead of using files or environment variables.

    Args:
        config: SW4RMConfig instance to set as global

    Example:
        config = SW4RMConfig(
            router_addr="localhost:50051",
            enable_metrics=False,
            log_level="DEBUG"
        )
        set_config(config)
    """
    global _global_config
    _global_config = config

