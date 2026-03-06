"""SW4RM LLM - LLM client abstraction for SW4RM agents.

This module provides a unified interface for LLM interactions, supporting:
- Groq API (API key from ~/.groq or GROQ_API_KEY)
- Anthropic API (API key from ~/.anthropic or ANTHROPIC_API_KEY)
- Claude Agent SDK (subscription-based authentication)
- Mock client for testing

Usage:
    ```python
    from sw4rm.llm import create_llm_client

    # Create client via environment (LLM_CLIENT_TYPE=groq|anthropic|claude_sdk|mock)
    client = create_llm_client()

    # Or explicitly
    client = create_llm_client(client_type="groq")

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
from sw4rm.llm.rate_limiter import (
    RateLimiterConfig,
    TokenBucket,
    get_global_rate_limiter,
    reset_global_rate_limiter,
)


# Lazy imports for optional-dependency clients
def __getattr__(name: str):
    if name == "ClaudeSDKClient":
        from sw4rm.llm.claude_sdk import ClaudeSDKClient
        return ClaudeSDKClient
    if name == "GroqClient":
        from sw4rm.llm.groq import GroqClient
        return GroqClient
    if name == "AnthropicClient":
        from sw4rm.llm.anthropic import AnthropicClient
        return AnthropicClient
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
    # rate_limiter.py
    "RateLimiterConfig",
    "TokenBucket",
    "get_global_rate_limiter",
    "reset_global_rate_limiter",
    # groq.py (lazy loaded)
    "GroqClient",
    # anthropic.py (lazy loaded)
    "AnthropicClient",
    # claude_sdk.py (lazy loaded)
    "ClaudeSDKClient",
]
