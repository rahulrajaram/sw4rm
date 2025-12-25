"""Semantic content types for SW4RM Protocol.

This module provides standardized content type constants and a registry for
semantic message content types based on CommOnt research. Content types enable
agents to understand message intent and validate payloads structurally.

Based on SPEC_REQUESTS.md section 1 (Vendor Content Types) and section 6.1
(Negotiation Room Pattern).
"""
from __future__ import annotations

import json
import re
from typing import Dict, Optional, Tuple


# Standard SW4RM content type constants
# These follow the pattern: application/vnd.sw4rm.<category>.<type>+json[;v=<version>]

# Intent-related content types
INTENT_QUERY = "application/vnd.sw4rm.intent.query+json"
INTENT_ACTION = "application/vnd.sw4rm.intent.action+json"

# Shared context content type
SHARED_CONTEXT = "application/vnd.sw4rm.shared-context+json"

# Scheduler content types (from SPEC_REQUESTS.md)
SCHEDULER_SEED = "application/vnd.sw4rm.scheduler.seed+json;v=1"
SCHEDULER_COMMAND = "application/vnd.sw4rm.scheduler.command+json;v=1"
AGENT_REPORT = "application/vnd.sw4rm.agent.report+json;v=1"

# Negotiation content types (from SPEC_REQUESTS.md section 6.1)
NEGOTIATION_PROPOSAL = "application/vnd.sw4rm.negotiation.proposal+json"
NEGOTIATION_VOTE = "application/vnd.sw4rm.negotiation.vote+json"

# Tool-related content types
TOOL_CALL = "application/vnd.sw4rm.tool.call+json"
TOOL_RESULT = "application/vnd.sw4rm.tool.result+json"


class ContentTypeRegistry:
    """Registry for managing content types and their schemas.

    This class provides a centralized registry for content types, allowing
    registration of JSON schemas for validation and metadata extraction.
    It supports parsing content type strings with parameters and extracting
    semantic intent from content type identifiers.

    Example:
        >>> registry = ContentTypeRegistry()
        >>> schema = {
        ...     "type": "object",
        ...     "properties": {"seed": {"type": "string"}},
        ...     "required": ["seed"]
        ... }
        >>> registry.register(SCHEDULER_SEED, schema)
        >>> registry.validate(SCHEDULER_SEED, b'{"seed": "task-123"}')
        True
    """

    def __init__(self) -> None:
        """Initialize an empty content type registry."""
        self._schemas: Dict[str, dict] = {}

    def register(self, content_type: str, schema: Optional[dict] = None) -> None:
        """Register a content type with an optional JSON schema.

        Args:
            content_type: The content type identifier (e.g., 'application/vnd.sw4rm.scheduler.seed+json;v=1')
            schema: Optional JSON schema dictionary for payload validation

        Example:
            >>> registry = ContentTypeRegistry()
            >>> schema = {"type": "object", "properties": {"seed": {"type": "string"}}}
            >>> registry.register("application/vnd.sw4rm.scheduler.seed+json;v=1", schema)
        """
        # Normalize content type by removing parameters for storage key
        base_type, _ = self.parse_content_type(content_type)
        self._schemas[base_type] = schema if schema is not None else {}

    def get_schema(self, content_type: str) -> Optional[dict]:
        """Retrieve the JSON schema for a content type.

        Args:
            content_type: The content type identifier

        Returns:
            The JSON schema dictionary if registered, None otherwise

        Example:
            >>> registry = ContentTypeRegistry()
            >>> registry.register("application/json", {"type": "object"})
            >>> schema = registry.get_schema("application/json")
            >>> schema["type"]
            'object'
        """
        base_type, _ = self.parse_content_type(content_type)
        return self._schemas.get(base_type)

    def validate(self, content_type: str, payload: bytes) -> bool:
        """Validate a payload against the registered schema for a content type.

        Args:
            content_type: The content type identifier
            payload: The payload bytes to validate

        Returns:
            True if validation succeeds or no schema is registered, False otherwise

        Example:
            >>> registry = ContentTypeRegistry()
            >>> schema = {"type": "object", "properties": {"seed": {"type": "string"}}, "required": ["seed"]}
            >>> registry.register("application/vnd.sw4rm.scheduler.seed+json;v=1", schema)
            >>> registry.validate("application/vnd.sw4rm.scheduler.seed+json;v=1", b'{"seed": "task-123"}')
            True
            >>> registry.validate("application/vnd.sw4rm.scheduler.seed+json;v=1", b'{"invalid": "data"}')
            False
        """
        schema = self.get_schema(content_type)

        # If no schema registered, consider it valid (permissive)
        if schema is None or not schema:
            return True

        try:
            # Parse payload as JSON
            data = json.loads(payload.decode("utf-8"))

            # Basic validation - check required fields and types
            return self._validate_against_schema(data, schema)

        except (json.JSONDecodeError, UnicodeDecodeError, ValueError):
            return False

    def _validate_against_schema(self, data: dict, schema: dict) -> bool:
        """Perform basic JSON schema validation.

        This is a lightweight validator that checks:
        - Type constraints
        - Required fields
        - Property types

        For full JSON Schema validation, consider using jsonschema library.

        Args:
            data: The parsed JSON data
            schema: The JSON schema to validate against

        Returns:
            True if validation succeeds, False otherwise
        """
        # Check type constraint
        if "type" in schema:
            expected_type = schema["type"]
            if expected_type == "object" and not isinstance(data, dict):
                return False
            elif expected_type == "array" and not isinstance(data, list):
                return False
            elif expected_type == "string" and not isinstance(data, str):
                return False
            elif expected_type == "number" and not isinstance(data, (int, float)):
                return False
            elif expected_type == "boolean" and not isinstance(data, bool):
                return False

        # Check required fields
        if "required" in schema and isinstance(data, dict):
            for field in schema["required"]:
                if field not in data:
                    return False

        # Check property types
        if "properties" in schema and isinstance(data, dict):
            for prop_name, prop_schema in schema["properties"].items():
                if prop_name in data:
                    # Recursively validate nested properties
                    if not self._validate_against_schema(data[prop_name], prop_schema):
                        return False

        return True

    def parse_content_type(self, ct: str) -> Tuple[str, Dict[str, str]]:
        """Parse a content type string into base type and parameters.

        Extracts the base media type and any parameters (e.g., version, charset).

        Args:
            ct: The content type string (e.g., 'application/json;v=1;charset=utf-8')

        Returns:
            A tuple of (base_type, parameters_dict)

        Example:
            >>> registry = ContentTypeRegistry()
            >>> base, params = registry.parse_content_type("application/vnd.sw4rm.scheduler.seed+json;v=1")
            >>> base
            'application/vnd.sw4rm.scheduler.seed+json'
            >>> params
            {'v': '1'}
        """
        # Split by semicolon to separate base type from parameters
        parts = ct.split(";")
        base_type = parts[0].strip()

        # Parse parameters
        params: Dict[str, str] = {}
        for part in parts[1:]:
            part = part.strip()
            if "=" in part:
                key, value = part.split("=", 1)
                params[key.strip()] = value.strip()
            else:
                # Parameter without value (flag)
                params[part] = ""

        return base_type, params

    def get_intent(self, content_type: str) -> Optional[str]:
        """Extract the intent from a SW4RM content type.

        Analyzes the content type structure to determine the semantic intent.
        For SW4RM vendor types, extracts the category and type portion.

        Args:
            content_type: The content type identifier

        Returns:
            The extracted intent string, or None if not a SW4RM vendor type

        Example:
            >>> registry = ContentTypeRegistry()
            >>> registry.get_intent("application/vnd.sw4rm.scheduler.seed+json;v=1")
            'scheduler.seed'
            >>> registry.get_intent("application/vnd.sw4rm.intent.query+json")
            'intent.query'
            >>> registry.get_intent("application/json")
            None
        """
        base_type, _ = self.parse_content_type(content_type)

        # Pattern: application/vnd.sw4rm.<category>.<type>+<format>
        # Example: application/vnd.sw4rm.scheduler.seed+json
        pattern = r"^application/vnd\.sw4rm\.([a-z0-9_\-\.]+)\+\w+$"
        match = re.match(pattern, base_type)

        if match:
            # Extract the intent portion (e.g., "scheduler.seed")
            return match.group(1)

        return None


# Global default registry instance
_default_registry = ContentTypeRegistry()


def get_default_registry() -> ContentTypeRegistry:
    """Get the global default content type registry.

    Returns:
        The default ContentTypeRegistry instance

    Example:
        >>> registry = get_default_registry()
        >>> registry.register("application/json", {"type": "object"})
    """
    return _default_registry


def register_standard_types(registry: Optional[ContentTypeRegistry] = None) -> None:
    """Register all standard SW4RM content types with basic schemas.

    This function registers the standard content types defined in this module
    with their corresponding JSON schemas for validation.

    Args:
        registry: Optional registry to use. If None, uses the default global registry.

    Example:
        >>> registry = ContentTypeRegistry()
        >>> register_standard_types(registry)
        >>> schema = registry.get_schema(SCHEDULER_SEED)
        >>> schema is not None
        True
    """
    if registry is None:
        registry = _default_registry

    # Scheduler seed schema
    registry.register(
        SCHEDULER_SEED,
        {
            "type": "object",
            "properties": {"seed": {"type": "string"}},
            "required": ["seed"],
        },
    )

    # Scheduler command schema
    registry.register(
        SCHEDULER_COMMAND,
        {
            "type": "object",
            "properties": {
                "schema_version": {"type": "number"},
                "to": {"type": "string"},
                "stage": {"type": "string"},
                "params": {"type": "object"},
            },
            "required": ["to", "stage"],
        },
    )

    # Agent report schema
    registry.register(
        AGENT_REPORT,
        {
            "type": "object",
            "properties": {
                "schema_version": {"type": "number"},
                "stage": {"type": "string"},
                "status": {"type": "string"},
                "logs": {"type": "string"},
                "diagnostics": {"type": "object"},
            },
            "required": ["stage", "status"],
        },
    )

    # Negotiation proposal schema
    registry.register(
        NEGOTIATION_PROPOSAL,
        {
            "type": "object",
            "properties": {
                "artifact_type": {"type": "string"},
                "artifact_id": {"type": "string"},
                "producer_id": {"type": "string"},
                "artifact": {"type": "object"},
                "requested_critics": {"type": "array"},
            },
            "required": ["artifact_type", "artifact_id", "producer_id", "artifact"],
        },
    )

    # Negotiation vote schema
    registry.register(
        NEGOTIATION_VOTE,
        {
            "type": "object",
            "properties": {
                "artifact_id": {"type": "string"},
                "critic_id": {"type": "string"},
                "score": {"type": "number"},
                "passed": {"type": "boolean"},
                "strengths": {"type": "array"},
                "weaknesses": {"type": "array"},
                "recommendations": {"type": "array"},
            },
            "required": ["artifact_id", "critic_id", "score", "passed"],
        },
    )

    # Shared context schema
    registry.register(
        SHARED_CONTEXT,
        {
            "type": "object",
            "properties": {
                "context_id": {"type": "string"},
                "version": {"type": "string"},
                "data": {"type": "object"},
            },
            "required": ["context_id", "version", "data"],
        },
    )

    # Intent types (minimal schemas)
    registry.register(
        INTENT_QUERY,
        {
            "type": "object",
            "properties": {"query": {"type": "string"}},
            "required": ["query"],
        },
    )

    registry.register(
        INTENT_ACTION,
        {
            "type": "object",
            "properties": {"action": {"type": "string"}},
            "required": ["action"],
        },
    )

    # Tool types
    registry.register(
        TOOL_CALL,
        {
            "type": "object",
            "properties": {
                "tool_name": {"type": "string"},
                "arguments": {"type": "object"},
            },
            "required": ["tool_name"],
        },
    )

    registry.register(
        TOOL_RESULT,
        {
            "type": "object",
            "properties": {
                "tool_name": {"type": "string"},
                "result": {},  # Any type
            },
            "required": ["tool_name"],
        },
    )
