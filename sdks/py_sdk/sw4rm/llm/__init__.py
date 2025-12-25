"""SW4RM LLM - LLM client abstraction for SW4RM agents.

This module provides a unified interface for LLM interactions, supporting:
- Claude Agent SDK (subscription-based authentication)
- Mock client for testing

The Claude Agent SDK client uses subscription authentication via
~/.claude/.credentials.json, avoiding the need for explicit API keys.

Usage:
    ```python
    from sw4rm.llm import create_llm_client

    # Create client (auto-detects credentials)
    client = create_llm_client()

    # Query the LLM
    response = await client.query(
        "Analyze this task and suggest next steps",
        system_prompt="You are a helpful task analysis agent."
    )
    print(response.content)

    # Stream responses
    async for chunk in client.stream_query("Generate a report"):
        print(chunk, end="")
    ```

For testing:
    ```python
    from sw4rm.llm import create_llm_client, MockLLMClient

    # Use environment variable
    # export LLM_CLIENT_TYPE=mock
    client = create_llm_client()

    # Or explicitly
    client = MockLLMClient(responses=["Test response 1", "Test response 2"])
    ```
"""

from sw4rm.llm.client import (
    LLMClient,
    LLMResponse,
    LLMError,
    LLMAuthenticationError,
    LLMRateLimitError,
    LLMTimeoutError,
    LLMContextLengthError,
)
from sw4rm.llm.factory import create_llm_client
from sw4rm.llm.mock import MockLLMClient

# Lazy import for ClaudeSDKClient to avoid requiring claude-agent-sdk
def __getattr__(name: str):
    if name == "ClaudeSDKClient":
        from sw4rm.llm.claude_sdk import ClaudeSDKClient
        return ClaudeSDKClient
    raise AttributeError(f"module {__name__!r} has no attribute {name!r}")


__version__ = "0.1.0"

__all__ = [
    # client.py - Interface and exceptions
    "LLMClient",
    "LLMResponse",
    "LLMError",
    "LLMAuthenticationError",
    "LLMRateLimitError",
    "LLMTimeoutError",
    "LLMContextLengthError",
    # factory.py
    "create_llm_client",
    # mock.py
    "MockLLMClient",
    # claude_sdk.py (lazy loaded)
    "ClaudeSDKClient",
]
