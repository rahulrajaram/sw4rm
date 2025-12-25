"""Mock LLM client for testing.

Provides deterministic responses without making actual API calls.
"""

from __future__ import annotations

import logging
from typing import Any, AsyncIterator, Callable, Optional

from sw4rm.llm.client import LLMClient, LLMResponse

logger = logging.getLogger(__name__)


class MockLLMClient(LLMClient):
    """Mock LLM client for testing without API calls.

    Returns configurable responses for testing purposes.

    Example:
        ```python
        from sw4rm.llm import MockLLMClient

        # Simple usage - returns echo of prompt
        client = MockLLMClient()
        response = await client.query("Hello")
        print(response.content)  # "Mock response to: Hello"

        # Custom responses
        client = MockLLMClient(
            responses=["First response", "Second response"]
        )

        # Custom response generator
        def my_generator(prompt: str) -> str:
            if "error" in prompt.lower():
                raise ValueError("Simulated error")
            return f"Processed: {prompt}"

        client = MockLLMClient(response_generator=my_generator)
        ```
    """

    def __init__(
        self,
        *,
        default_model: str = "mock-model",
        responses: Optional[list[str]] = None,
        response_generator: Optional[Callable[[str], str]] = None,
    ):
        """Initialize mock client.

        Args:
            default_model: Model name to return in responses.
            responses: List of responses to return in order (cycles).
            response_generator: Function to generate responses from prompts.
        """
        self.default_model = default_model
        self._responses = responses or []
        self._response_index = 0
        self._response_generator = response_generator
        self._call_count = 0
        self._call_history: list[dict[str, Any]] = []

        logger.info("Initialized Mock LLM client")

    @property
    def call_count(self) -> int:
        """Number of queries made to this client."""
        return self._call_count

    @property
    def call_history(self) -> list[dict[str, Any]]:
        """History of all calls made to this client."""
        return self._call_history

    def reset(self) -> None:
        """Reset call count and history."""
        self._call_count = 0
        self._call_history = []
        self._response_index = 0

    async def query(
        self,
        prompt: str,
        *,
        system_prompt: Optional[str] = None,
        max_tokens: int = 4096,
        temperature: float = 1.0,
        model: Optional[str] = None,
    ) -> LLMResponse:
        """Return a mock response.

        Args:
            prompt: The prompt (recorded in history).
            system_prompt: Optional system prompt (recorded in history).
            max_tokens: Max tokens (recorded in history).
            temperature: Temperature (recorded in history).
            model: Model override.

        Returns:
            LLMResponse with mock content.
        """
        self._call_count += 1
        self._call_history.append({
            "prompt": prompt,
            "system_prompt": system_prompt,
            "max_tokens": max_tokens,
            "temperature": temperature,
            "model": model or self.default_model,
        })

        # Generate response
        if self._response_generator:
            content = self._response_generator(prompt)
        elif self._responses:
            content = self._responses[self._response_index % len(self._responses)]
            self._response_index += 1
        else:
            content = f"Mock response to: {prompt[:100]}"

        return LLMResponse(
            content=content,
            model=model or self.default_model,
            usage={"input_tokens": len(prompt) // 4, "output_tokens": len(content) // 4},
            metadata={"mock": True, "call_count": self._call_count},
        )

    async def stream_query(
        self,
        prompt: str,
        *,
        system_prompt: Optional[str] = None,
        max_tokens: int = 4096,
        temperature: float = 1.0,
        model: Optional[str] = None,
    ) -> AsyncIterator[str]:
        """Stream a mock response.

        Yields the response in small chunks to simulate streaming.
        """
        response = await self.query(
            prompt,
            system_prompt=system_prompt,
            max_tokens=max_tokens,
            temperature=temperature,
            model=model,
        )

        # Simulate streaming by yielding words
        words = response.content.split()
        for i, word in enumerate(words):
            yield word + (" " if i < len(words) - 1 else "")
