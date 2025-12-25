"""Factory for creating LLM clients.

Provides a simple way to create the appropriate LLM client based on
environment configuration or explicit parameters.
"""

from __future__ import annotations

import logging
import os
from typing import Any, Optional

from sw4rm.llm.client import LLMClient

logger = logging.getLogger(__name__)


def create_llm_client(
    *,
    client_type: Optional[str] = None,
    model: str = "sonnet",
    **kwargs: Any,
) -> LLMClient:
    """Create an LLM client based on environment or explicit type.

    This factory function creates the appropriate LLM client based on:
    1. Explicit client_type parameter
    2. LLM_CLIENT_TYPE environment variable
    3. Default to "claude_sdk" (subscription auth)

    Environment variables:
        LLM_CLIENT_TYPE: "claude_sdk" or "mock" (default: "claude_sdk")
        LLM_DEFAULT_MODEL: Default model to use (default: "sonnet")

    Args:
        client_type: Override client type ("claude_sdk" or "mock").
        model: Default model to use (sonnet, opus, haiku).
        **kwargs: Additional arguments for client constructor.

    Returns:
        LLMClient instance.

    Raises:
        ValueError: If invalid client_type is specified.
        LLMError: If client initialization fails.

    Example:
        ```python
        from sw4rm.llm import create_llm_client

        # Auto-detect (uses Claude SDK by default)
        client = create_llm_client()

        # Explicit Claude SDK with opus model
        client = create_llm_client(client_type="claude_sdk", model="opus")

        # Mock client for testing
        client = create_llm_client(client_type="mock")

        # Use environment variable
        # export LLM_CLIENT_TYPE=mock
        client = create_llm_client()  # Creates MockLLMClient
        ```
    """
    # Determine client type
    if client_type is None:
        client_type = os.getenv("LLM_CLIENT_TYPE", "claude_sdk")
    client_type = client_type.lower()

    # Get model from environment if not overridden
    model = os.getenv("LLM_DEFAULT_MODEL", model)

    # Create appropriate client
    if client_type == "mock":
        from sw4rm.llm.mock import MockLLMClient

        logger.info("Creating Mock LLM client")
        return MockLLMClient(default_model=model, **kwargs)

    elif client_type == "claude_sdk":
        from sw4rm.llm.claude_sdk import ClaudeSDKClient

        logger.info("Creating Claude SDK client (uses subscription auth)")
        return ClaudeSDKClient(default_model=model, **kwargs)

    else:
        raise ValueError(
            f"Unknown LLM client type: {client_type}. "
            f"Valid types: 'claude_sdk', 'mock'"
        )
