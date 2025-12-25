"""Abstract LLM client interface.

This module provides the base interface for LLM clients used by SW4RM agents.
Implementations can use Anthropic API directly, Claude Agent SDK (subscription),
or mock clients for testing.
"""

from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from typing import Any, AsyncIterator, Optional


@dataclass
class LLMResponse:
    """Response from an LLM API call.

    Attributes:
        content: The generated text content.
        model: The model that generated the response.
        usage: Token usage statistics (if available).
        metadata: Additional response metadata.
    """

    content: str
    model: str
    usage: Optional[dict[str, Any]] = None
    metadata: Optional[dict[str, Any]] = field(default_factory=dict)


class LLMClient(ABC):
    """Abstract interface for LLM clients.

    All LLM client implementations must implement this interface.
    This allows SW4RM agents to be provider-agnostic.

    Implementations:
        - ClaudeSDKClient: Uses Claude Agent SDK (subscription auth)
        - AnthropicClient: Uses Anthropic API directly (API key)
        - MockClient: For testing without API calls

    Example:
        ```python
        from sw4rm.llm import create_llm_client

        # Create client (auto-detects best option)
        client = create_llm_client()

        # Query the LLM
        response = await client.query(
            "Analyze this data and suggest next steps",
            system_prompt="You are a helpful data analyst agent."
        )
        print(response.content)
        ```
    """

    @abstractmethod
    async def query(
        self,
        prompt: str,
        *,
        system_prompt: Optional[str] = None,
        max_tokens: int = 4096,
        temperature: float = 1.0,
        model: Optional[str] = None,
    ) -> LLMResponse:
        """Send a query to the LLM and get a complete response.

        Args:
            prompt: The user prompt/query to send.
            system_prompt: Optional system prompt for context.
            max_tokens: Maximum tokens to generate.
            temperature: Sampling temperature (0.0-2.0).
            model: Override the default model.

        Returns:
            LLMResponse with the generated content and metadata.

        Raises:
            LLMError: On API errors or failures.
            LLMAuthenticationError: On authentication failures.
            LLMRateLimitError: When rate limits are exceeded.
            LLMTimeoutError: When the request times out.
        """
        pass

    @abstractmethod
    async def stream_query(
        self,
        prompt: str,
        *,
        system_prompt: Optional[str] = None,
        max_tokens: int = 4096,
        temperature: float = 1.0,
        model: Optional[str] = None,
    ) -> AsyncIterator[str]:
        """Stream a query response chunk by chunk.

        Args:
            prompt: The user prompt/query to send.
            system_prompt: Optional system prompt for context.
            max_tokens: Maximum tokens to generate.
            temperature: Sampling temperature (0.0-2.0).
            model: Override the default model.

        Yields:
            Text chunks as they arrive from the API.

        Raises:
            LLMError: On API errors or failures.
        """
        pass


# ---------------------------------------------------------------------------
# Exception Hierarchy
# ---------------------------------------------------------------------------


class LLMError(Exception):
    """Base exception for all LLM client errors."""

    pass


class LLMAuthenticationError(LLMError):
    """Raised when API authentication fails.

    Common causes:
    - Invalid API key
    - Expired OAuth token
    - Missing credentials
    """

    pass


class LLMRateLimitError(LLMError):
    """Raised when API rate limits are exceeded.

    The caller should implement exponential backoff when handling this.
    """

    pass


class LLMTimeoutError(LLMError):
    """Raised when an API request times out.

    Consider increasing the timeout or simplifying the prompt.
    """

    pass


class LLMContextLengthError(LLMError):
    """Raised when the prompt exceeds the model's context length.

    Consider truncating the prompt or using a model with larger context.
    """

    pass
