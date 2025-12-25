# Copyright 2025 Rahul Rajaram
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""Feature flags for SW4RM SDK.

This module provides a feature flag system for enabling/disabling experimental
or optional features in the SW4RM SDK. Feature flags can be configured via:
- SW4RMConfig.feature_flags dictionary
- Environment variables (SW4RM_FEATURE_*)
- Programmatic API

Standard feature flags control major SDK capabilities like workflow management,
handoff protocols, audit logging, and voting mechanisms.
"""

from __future__ import annotations

import os
from typing import Any, Optional

# Import config module for accessing global configuration
try:
    from . import config as sw4rm_config
except ImportError:
    sw4rm_config = None  # type: ignore


class FeatureFlags:
    """Feature flag manager for SW4RM SDK.

    Provides methods to check if features are enabled and retrieve feature
    flag values. Flags can be loaded from configuration or set programmatically.

    The flag resolution order is:
    1. Programmatic overrides (set via set_flag)
    2. Environment variables (SW4RM_FEATURE_*)
    3. Configuration file (feature_flags section)
    4. Default values

    Example:
        flags = FeatureFlags()

        # Check if workflow is enabled
        if flags.is_enabled("ENABLE_WORKFLOW"):
            # Use workflow features
            pass

        # Get flag value with default
        max_retries = flags.get_value("MAX_RETRIES", default=3)

        # Programmatically enable a feature
        flags.set_flag("ENABLE_AUDIT", True)
    """

    # Standard feature flag names
    ENABLE_WORKFLOW = "ENABLE_WORKFLOW"
    ENABLE_HANDOFF = "ENABLE_HANDOFF"
    ENABLE_AUDIT = "ENABLE_AUDIT"
    ENABLE_VOTING = "ENABLE_VOTING"

    def __init__(self, config_flags: Optional[dict[str, Any]] = None) -> None:
        """Initialize the feature flag manager.

        Args:
            config_flags: Optional dictionary of feature flags to use.
                         If None, loads from global SW4RMConfig.
        """
        self._overrides: dict[str, Any] = {}

        # Load flags from config if available
        if config_flags is not None:
            self._config_flags = config_flags
        elif sw4rm_config is not None:
            try:
                cfg = sw4rm_config.get_config()
                self._config_flags = cfg.feature_flags
            except Exception:
                self._config_flags = {}
        else:
            self._config_flags = {}

    def is_enabled(self, flag_name: str) -> bool:
        """Check if a feature flag is enabled.

        A flag is considered enabled if its value is truthy (True, 1, "true", etc.).

        Args:
            flag_name: Name of the feature flag to check

        Returns:
            True if the flag is enabled, False otherwise

        Example:
            if flags.is_enabled(FeatureFlags.ENABLE_WORKFLOW):
                # Workflow is enabled
                setup_workflow()
        """
        value = self.get_value(flag_name)

        # Handle various truthy representations
        if isinstance(value, bool):
            return value
        elif isinstance(value, (int, float)):
            return value != 0
        elif isinstance(value, str):
            return value.lower() in ("true", "1", "yes", "on", "enabled")
        else:
            return bool(value)

    def get_value(self, flag_name: str, default: Any = None) -> Any:
        """Get the value of a feature flag.

        Resolution order:
        1. Programmatic overrides (set via set_flag)
        2. Environment variables (SW4RM_FEATURE_{flag_name})
        3. Configuration file (feature_flags section)
        4. Default value

        Args:
            flag_name: Name of the feature flag
            default: Default value to return if flag is not set

        Returns:
            The flag value, or default if not set

        Example:
            # Get flag with default
            max_retries = flags.get_value("MAX_RETRIES", default=3)

            # Get boolean flag
            enabled = flags.get_value("ENABLE_FEATURE", default=False)
        """
        # Check programmatic overrides first
        if flag_name in self._overrides:
            return self._overrides[flag_name]

        # Check environment variables
        env_key = f"SW4RM_FEATURE_{flag_name}"
        if env_key in os.environ:
            return _parse_env_value(os.environ[env_key])

        # Check configuration
        if flag_name in self._config_flags:
            return self._config_flags[flag_name]

        # Return default
        return default

    def set_flag(self, flag_name: str, value: Any) -> None:
        """Set a feature flag programmatically.

        This creates an override that takes precedence over environment
        variables and configuration files.

        Args:
            flag_name: Name of the feature flag
            value: Value to set (can be any type)

        Example:
            # Enable a feature
            flags.set_flag(FeatureFlags.ENABLE_AUDIT, True)

            # Set numeric flag
            flags.set_flag("MAX_CONNECTIONS", 100)

            # Set string flag
            flags.set_flag("DEPLOYMENT_ENV", "production")
        """
        self._overrides[flag_name] = value

    def clear_flag(self, flag_name: str) -> None:
        """Clear a programmatic flag override.

        After clearing, the flag will be resolved from environment or config.

        Args:
            flag_name: Name of the feature flag to clear

        Example:
            flags.set_flag("ENABLE_AUDIT", True)
            # ... later ...
            flags.clear_flag("ENABLE_AUDIT")  # Now uses env/config value
        """
        if flag_name in self._overrides:
            del self._overrides[flag_name]

    def get_all_flags(self) -> dict[str, Any]:
        """Get all feature flags and their current values.

        Returns a dictionary containing all flags from configuration,
        environment, and programmatic overrides, with overrides taking
        precedence.

        Returns:
            Dictionary of flag names to values

        Example:
            flags = feature_flags.get_all_flags()
            for name, value in flags.items():
                print(f"{name}: {value}")
        """
        # Start with config flags
        all_flags = dict(self._config_flags)

        # Add environment variables
        for key, value in os.environ.items():
            if key.startswith("SW4RM_FEATURE_"):
                flag_name = key[len("SW4RM_FEATURE_"):]
                all_flags[flag_name] = _parse_env_value(value)

        # Apply overrides
        all_flags.update(self._overrides)

        return all_flags


def _parse_env_value(value: str) -> Any:
    """Parse an environment variable value to appropriate type.

    Tries to convert to int, float, or bool. Falls back to string.

    Args:
        value: String value from environment variable

    Returns:
        Parsed value (int, float, bool, or str)
    """
    # Try boolean
    if value.lower() in ("true", "yes", "on", "enabled"):
        return True
    elif value.lower() in ("false", "no", "off", "disabled"):
        return False

    # Try integer
    try:
        return int(value)
    except ValueError:
        pass

    # Try float
    try:
        return float(value)
    except ValueError:
        pass

    # Return as string
    return value


# Global singleton instance
_global_flags: Optional[FeatureFlags] = None


def get_feature_flags() -> FeatureFlags:
    """Get the global feature flags instance.

    Returns the singleton FeatureFlags instance, creating it if needed.
    The instance is initialized with flags from the global SW4RMConfig.

    Returns:
        Global FeatureFlags instance

    Example:
        flags = get_feature_flags()
        if flags.is_enabled(FeatureFlags.ENABLE_WORKFLOW):
            # Workflow is enabled globally
            pass
    """
    global _global_flags

    if _global_flags is None:
        _global_flags = FeatureFlags()

    return _global_flags


def set_feature_flags(flags: FeatureFlags) -> None:
    """Set the global feature flags instance.

    This allows applications to use a custom FeatureFlags instance
    with specific configuration.

    Args:
        flags: FeatureFlags instance to set as global

    Example:
        custom_flags = FeatureFlags(config_flags={
            FeatureFlags.ENABLE_WORKFLOW: True,
            FeatureFlags.ENABLE_AUDIT: False,
        })
        set_feature_flags(custom_flags)
    """
    global _global_flags
    _global_flags = flags
