"""Groq LLM client for SW4RM agents.

Thin wrapper around the Groq SDK. No tool-calling or diagnostic mode —
just prompt in, text out, with rate limiting.

Credentials (in order):
    1. api_key constructor parameter
    2. GROQ_API_KEY environment variable
    3. ~/.groq file
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

# Import groq for exception type checks
try:
    import groq as _groq_mod
except ImportError:
    _groq_mod = None  # type: ignore[assignment]

DEFAULT_MODEL = "llama-3.3-70b-versatile"


class GroqClient(LLMClient):
    """LLM client for Groq API.

    Credentials resolved from (in order):
        1. ``api_key`` constructor parameter
        2. ``GROQ_API_KEY`` environment variable
        3. ``~/.groq`` file (plain text, one line)

    Environment variables:
        GROQ_API_KEY: API key override
        GROQ_DEFAULT_MODEL: Default model override
    """

    def __init__(
        self,
        *,
        api_key: Optional[str] = None,
        default_model: Optional[str] = None,
        timeout: int = 120,
    ):
        self.default_model = (
            default_model
            or os.getenv("GROQ_DEFAULT_MODEL")
            or DEFAULT_MODEL
        )

        env_key = os.getenv("GROQ_API_KEY")
        if env_key:
            env_key = env_key.strip()
        self.api_key = api_key or env_key or self._load_key_file()

        if not self.api_key:
            raise LLMAuthenticationError(
                "No Groq API key. Set GROQ_API_KEY, pass api_key, or create ~/.groq"
            )

        try:
            from groq import AsyncGroq
        except ImportError as e:
            raise LLMError("Groq SDK not installed. Run: pip install groq") from e

        self._client = AsyncGroq(api_key=self.api_key, timeout=timeout)
        self._rate_limiter = get_global_rate_limiter()

    @staticmethod
    def _load_key_file() -> Optional[str]:
        """Load API key from ~/.groq file."""
        try:
            path = Path.home() / ".groq"
            if path.exists():
                return path.read_text().strip()
        except Exception:
            pass
        return None

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
        """Send a query to Groq and get a complete response."""
        use_model = model or self.default_model
        estimated = self._estimate_tokens(prompt, system_prompt)
        await self._rate_limiter.acquire(estimated)

        messages: list[dict[str, Any]] = []
        if system_prompt:
            messages.append({"role": "system", "content": system_prompt})
        messages.append({"role": "user", "content": prompt})

        try:
            response = await self._client.chat.completions.create(
                model=use_model,
                messages=messages,
                max_tokens=max_tokens,
                temperature=temperature,
            )
        except Exception as e:
            if _groq_mod and isinstance(e, _groq_mod.RateLimitError):
                await self._rate_limiter.record_rate_limit()
                raise LLMRateLimitError(f"Groq rate limit exceeded: {e}") from e
            if _groq_mod and isinstance(e, _groq_mod.AuthenticationError):
                raise LLMAuthenticationError(f"Groq auth failed: {e}") from e
            if _groq_mod and isinstance(e, _groq_mod.APITimeoutError):
                raise LLMTimeoutError(f"Groq request timed out: {e}") from e
            raise LLMError(f"Groq API error: {e}") from e

        await self._rate_limiter.record_success()

        choice = response.choices[0]
        content = choice.message.content or ""

        usage = None
        if response.usage:
            usage = {
                "input_tokens": response.usage.prompt_tokens,
                "output_tokens": response.usage.completion_tokens,
            }

        return LLMResponse(
            content=content,
            model=response.model,
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

        messages: list[dict[str, Any]] = []
        if system_prompt:
            messages.append({"role": "system", "content": system_prompt})
        messages.append({"role": "user", "content": prompt})

        try:
            stream = await self._client.chat.completions.create(
                model=use_model,
                messages=messages,
                max_tokens=max_tokens,
                temperature=temperature,
                stream=True,
            )
        except Exception as e:
            if _groq_mod and isinstance(e, _groq_mod.RateLimitError):
                await self._rate_limiter.record_rate_limit()
                raise LLMRateLimitError(f"Groq rate limit exceeded: {e}") from e
            raise LLMError(f"Groq API error: {e}") from e

        stream_completed = False
        try:
            async for chunk in stream:
                if chunk.choices and chunk.choices[0].delta.content:
                    yield chunk.choices[0].delta.content
            stream_completed = True
        finally:
            if stream_completed:
                await self._rate_limiter.record_success()
