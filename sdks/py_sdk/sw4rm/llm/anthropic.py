"""Anthropic LLM client for SW4RM agents.

Thin wrapper around the Anthropic SDK. Handles system-message normalization
(Anthropic uses a top-level ``system`` param, not an in-band system message).

Credentials (in order):
    1. api_key constructor parameter
    2. ANTHROPIC_API_KEY environment variable
    3. ~/.anthropic file
"""

import logging
import os
from pathlib import Path
from typing import Any, AsyncIterator, Optional

from sw4rm.llm.client import (
    LLMAuthenticationError,
    LLMClient,
    LLMError,
    LLMRateLimitError,
    LLMResponse,
    LLMTimeoutError,
)
from sw4rm.llm.rate_limiter import get_global_rate_limiter

logger = logging.getLogger(__name__)

DEFAULT_MODEL = "claude-sonnet-4-20250514"


class AnthropicClient(LLMClient):
    """LLM client for Anthropic Claude API.

    Credentials resolved from (in order):
        1. ``api_key`` constructor parameter
        2. ``ANTHROPIC_API_KEY`` environment variable
        3. ``~/.anthropic`` file (plain text, one line)

    Environment variables:
        ANTHROPIC_API_KEY: API key override
        ANTHROPIC_DEFAULT_MODEL: Default model override
    """

    def __init__(
        self,
        *,
        api_key: Optional[str] = None,
        default_model: Optional[str] = None,
        timeout: int = 300,
    ):
        self.default_model = (
            default_model
            or os.getenv("ANTHROPIC_DEFAULT_MODEL")
            or DEFAULT_MODEL
        )

        env_key = os.getenv("ANTHROPIC_API_KEY")
        if env_key:
            env_key = env_key.strip()
        self.api_key = api_key or env_key or self._load_key_file()

        if not self.api_key:
            raise LLMAuthenticationError(
                "No Anthropic API key. Set ANTHROPIC_API_KEY, pass api_key, or create ~/.anthropic"
            )

        try:
            import anthropic  # type: ignore[import-not-found]
        except ImportError as e:
            raise LLMError(
                "Anthropic SDK not installed. Run: pip install anthropic"
            ) from e

        self._anthropic = anthropic
        self._client = anthropic.AsyncAnthropic(
            api_key=self.api_key, timeout=timeout
        )
        self._rate_limiter = get_global_rate_limiter()

    @staticmethod
    def _load_key_file() -> Optional[str]:
        """Load API key from ~/.anthropic file."""
        try:
            path = Path.home() / ".anthropic"
            if path.exists():
                return path.read_text().strip()
        except Exception:
            pass
        return None

    def _is_error_type(self, error: Exception, class_name: str) -> bool:
        """Safely check anthropic SDK exception class by name."""
        error_class = getattr(self._anthropic, class_name, None)
        return bool(error_class and isinstance(error, error_class))

    def _estimate_tokens(self, prompt: str, system_prompt: Optional[str]) -> int:
        """Rough token estimate (~4 chars per token)."""
        total = len(prompt)
        if system_prompt:
            total += len(system_prompt)
        return max(total // 4, 100)

    async def query(
        self,
        prompt: str,
        *,
        system_prompt: Optional[str] = None,
        max_tokens: int = 4096,
        temperature: float = 1.0,
        model: Optional[str] = None,
    ) -> LLMResponse:
        """Send a query to Anthropic and get a complete response."""
        use_model = model or self.default_model
        estimated = self._estimate_tokens(prompt, system_prompt)
        await self._rate_limiter.acquire(estimated)

        request_params: dict[str, Any] = {
            "model": use_model,
            "messages": [{"role": "user", "content": prompt}],
            "max_tokens": max_tokens,
            "temperature": temperature,
        }
        if system_prompt:
            request_params["system"] = system_prompt

        try:
            response = await self._client.messages.create(**request_params)
        except Exception as e:
            if self._is_error_type(e, "AuthenticationError") or self._is_error_type(
                e, "PermissionDeniedError"
            ):
                raise LLMAuthenticationError(f"Anthropic auth failed: {e}") from e
            if self._is_error_type(e, "RateLimitError"):
                await self._rate_limiter.record_rate_limit()
                raise LLMRateLimitError(f"Anthropic rate limit exceeded: {e}") from e
            if self._is_error_type(e, "APITimeoutError"):
                raise LLMTimeoutError(f"Anthropic request timed out: {e}") from e
            err_str = str(e).lower()
            if "credit balance" in err_str or "billing" in err_str:
                raise LLMAuthenticationError(f"Anthropic billing error: {e}") from e
            raise LLMError(f"Anthropic API error: {e}") from e

        await self._rate_limiter.record_success()

        # Extract text from content blocks
        text_parts: list[str] = []
        for block in getattr(response, "content", []) or []:
            text = getattr(block, "text", None)
            if isinstance(text, str):
                text_parts.append(text)
        content = "".join(text_parts).strip()

        usage_data = getattr(response, "usage", None)
        input_tokens = int(getattr(usage_data, "input_tokens", 0) or 0)
        output_tokens = int(getattr(usage_data, "output_tokens", 0) or 0)
        usage = {
            "input_tokens": input_tokens,
            "output_tokens": output_tokens,
        }

        return LLMResponse(
            content=content,
            model=getattr(response, "model", use_model),
            usage=usage,
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
        """Stream a query response chunk by chunk."""
        use_model = model or self.default_model
        estimated = self._estimate_tokens(prompt, system_prompt)
        await self._rate_limiter.acquire(estimated)

        request_params: dict[str, Any] = {
            "model": use_model,
            "messages": [{"role": "user", "content": prompt}],
            "max_tokens": max_tokens,
            "temperature": temperature,
        }
        if system_prompt:
            request_params["system"] = system_prompt

        stream_completed = False
        try:
            async with self._client.messages.stream(**request_params) as stream:
                async for text in stream.text_stream:
                    yield text
            stream_completed = True
        except GeneratorExit:
            # Caller broke out of the async generator early; do not
            # re-raise through the error-handling path below.
            return
        except Exception as e:
            if self._is_error_type(e, "RateLimitError"):
                await self._rate_limiter.record_rate_limit()
                raise LLMRateLimitError(f"Anthropic rate limit exceeded: {e}") from e
            raise LLMError(f"Anthropic API error: {e}") from e
        finally:
            if stream_completed:
                await self._rate_limiter.record_success()
