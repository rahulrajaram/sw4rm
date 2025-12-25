"""Claude Agent SDK LLM client implementation.

This module provides a robust wrapper around the Claude Agent SDK that handles
lifecycle management for sequential queries. Uses thread isolation by default
for maximum reliability.

The Claude Agent SDK uses subscription-based authentication via
~/.claude/.credentials.json, avoiding the need for explicit API keys.

Designed for Claude Agent SDK version: 0.1.x
"""

from __future__ import annotations

import asyncio
import logging
from typing import AsyncIterator, List, Optional

from sw4rm.llm.client import (
    LLMClient,
    LLMError,
    LLMResponse,
    LLMTimeoutError,
)

logger = logging.getLogger(__name__)

# SDK version compatibility
EXPECTED_SDK_VERSION = "0.1"


def _check_sdk_version() -> None:
    """Verify Claude Agent SDK version compatibility."""
    try:
        from claude_agent_sdk import __version__

        if not __version__.startswith(EXPECTED_SDK_VERSION):
            logger.warning(
                f"Claude Agent SDK version {__version__} may not be compatible. "
                f"This client was designed for version {EXPECTED_SDK_VERSION}.x"
            )
    except (ImportError, AttributeError):
        pass  # Version check will fail at actual usage


class ClaudeSDKClient(LLMClient):
    """LLM client using Claude Agent SDK with subscription authentication.

    This client wraps the Claude Agent SDK to provide a simple query interface.
    It handles the anyio cancel scope lifecycle issues by using thread isolation
    for each query, ensuring reliable sequential calls.

    No API key needed - uses ~/.claude/.credentials.json automatically via
    Claude Code subscription authentication.

    Attributes:
        default_model: Default model to use (sonnet, opus, haiku).
        max_turns: Maximum conversation turns per query.
        query_timeout_seconds: Maximum time to wait for response.

    Example:
        ```python
        from sw4rm.llm import ClaudeSDKClient

        client = ClaudeSDKClient(default_model="sonnet")

        response = await client.query(
            "What is the capital of France?",
            system_prompt="Answer concisely."
        )
        print(response.content)  # "Paris"
        ```
    """

    # Model name mapping for convenience
    MODEL_MAP = {
        "sonnet": "sonnet",
        "opus": "opus",
        "haiku": "haiku",
    }

    def __init__(
        self,
        *,
        default_model: str = "sonnet",
        max_turns: int = 1,
        query_timeout_seconds: float = 120.0,
    ):
        """Initialize Claude SDK client.

        Args:
            default_model: Default model to use (sonnet, opus, haiku).
            max_turns: Maximum conversation turns (default 1 for single query).
            query_timeout_seconds: Maximum time to wait for response.

        Raises:
            LLMError: If Claude Agent SDK is not installed.
        """
        self.default_model = self.MODEL_MAP.get(default_model, default_model)
        self.max_turns = max_turns
        self.query_timeout_seconds = query_timeout_seconds

        # Verify SDK is available
        try:
            from claude_agent_sdk import query  # noqa: F401

            _check_sdk_version()
        except ImportError as e:
            raise LLMError(
                "Claude Agent SDK not installed. Run: pip install claude-agent-sdk"
            ) from e

        logger.info(
            f"Initialized Claude SDK client with model: {self.default_model}"
        )

    async def query(
        self,
        prompt: str,
        *,
        system_prompt: Optional[str] = None,
        max_tokens: int = 4096,
        temperature: float = 1.0,
        model: Optional[str] = None,
    ) -> LLMResponse:
        """Send a query using Claude Agent SDK.

        Uses thread isolation to ensure reliable sequential queries.

        Args:
            prompt: The prompt to send.
            system_prompt: Optional system prompt to prepend.
            max_tokens: Maximum tokens (not used by SDK, included for interface).
            temperature: Temperature (not used by SDK, included for interface).
            model: Model override (sonnet, opus, haiku).

        Returns:
            LLMResponse with the model's response.

        Raises:
            LLMError: On API or SDK errors.
            LLMTimeoutError: If query exceeds timeout.
        """
        full_prompt = prompt
        if system_prompt:
            full_prompt = f"{system_prompt}\n\n{prompt}"

        resolved_model = self.MODEL_MAP.get(model, model) if model else self.default_model

        try:
            content = await self._query_in_thread(full_prompt, resolved_model)

            return LLMResponse(
                content=content,
                model=resolved_model,
                usage=None,  # SDK doesn't expose token counts
                metadata={"sdk": "claude-agent-sdk"},
            )

        except LLMTimeoutError:
            raise
        except Exception as e:
            logger.error(f"Claude SDK query failed: {e}")
            raise LLMError(f"Claude SDK error: {e}") from e

    async def _query_in_thread(
        self,
        prompt: str,
        model: str,
    ) -> str:
        """Run query in isolated thread with fresh event loop.

        This guarantees complete isolation by running each query in
        a separate thread with its own asyncio event loop.

        Args:
            prompt: The full prompt to send.
            model: The model to use.

        Returns:
            The response content.

        Raises:
            LLMTimeoutError: If query exceeds timeout.
        """
        import concurrent.futures

        def run_in_thread() -> str:
            """Execute query in fresh event loop."""
            from claude_agent_sdk import (
                query as sdk_query,
                ClaudeAgentOptions,
                AssistantMessage,
            )

            async def async_query() -> str:
                options = ClaudeAgentOptions(
                    max_turns=self.max_turns,
                    allowed_tools=[],
                    model=model,
                )

                content_parts: List[str] = []

                async for message in sdk_query(prompt=prompt, options=options):
                    if isinstance(message, AssistantMessage):
                        for block in message.content:
                            if hasattr(block, "text"):
                                content_parts.append(block.text)

                return "\n".join(content_parts)

            # Create fresh event loop for this thread
            loop = asyncio.new_event_loop()
            asyncio.set_event_loop(loop)
            try:
                return loop.run_until_complete(async_query())
            finally:
                loop.close()

        # Run in thread pool with timeout
        with concurrent.futures.ThreadPoolExecutor(max_workers=1) as executor:
            future = executor.submit(run_in_thread)
            try:
                done, _ = concurrent.futures.wait(
                    [future],
                    timeout=self.query_timeout_seconds
                )
                if future in done:
                    return future.result()
                else:
                    future.cancel()
                    raise LLMTimeoutError(
                        f"Query timed out after {self.query_timeout_seconds}s"
                    )
            except concurrent.futures.TimeoutError:
                future.cancel()
                raise LLMTimeoutError(
                    f"Query timed out after {self.query_timeout_seconds}s"
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
        """Stream a query response.

        Note: With thread isolation, this collects all content then yields
        it as a single chunk. True streaming would require task isolation
        which has reliability issues with sequential queries.

        Args:
            prompt: The prompt to send.
            system_prompt: Optional system prompt to prepend.
            max_tokens: Maximum tokens (not used by SDK).
            temperature: Temperature (not used by SDK).
            model: Model override.

        Yields:
            Response content (as single chunk with thread isolation).
        """
        response = await self.query(
            prompt,
            system_prompt=system_prompt,
            max_tokens=max_tokens,
            temperature=temperature,
            model=model,
        )
        if response.content:
            yield response.content
