"""Tests for SW4RM LLM module — rate limiter, factory, Groq client, Anthropic client."""

import asyncio
import os
import time
from pathlib import Path
from unittest.mock import AsyncMock, MagicMock, patch

import pytest

from sw4rm.llm.client import (
    LLMAuthenticationError,
    LLMClient,
    LLMError,
    LLMRateLimitError,
    LLMResponse,
    LLMTimeoutError,
)
from sw4rm.llm.rate_limiter import (
    RateLimiterConfig,
    TokenBucket,
    get_global_rate_limiter,
    reset_global_rate_limiter,
)
from sw4rm.llm.factory import create_llm_client
from sw4rm.llm.mock import MockLLMClient


# ---------------------------------------------------------------------------
# Rate Limiter Tests
# ---------------------------------------------------------------------------


class TestRateLimiterConfig:
    def test_defaults(self):
        cfg = RateLimiterConfig()
        assert cfg.tokens_per_minute == 250_000
        assert cfg.enabled is True
        assert cfg.adaptive_enabled is True
        assert cfg.reduction_factor == 0.7
        assert cfg.recovery_factor == 1.1
        assert cfg.cooldown_seconds == 30
        assert cfg.successes_for_recovery == 20

    def test_env_override(self, monkeypatch):
        monkeypatch.setenv("LLM_RATE_LIMIT_TOKENS_PER_MIN", "100000")
        monkeypatch.setenv("LLM_RATE_LIMIT_ENABLED", "0")
        cfg = RateLimiterConfig()
        assert cfg.tokens_per_minute == 100_000
        assert cfg.enabled is False


class TestTokenBucket:
    @pytest.fixture(autouse=True)
    def _reset(self):
        reset_global_rate_limiter()
        yield
        reset_global_rate_limiter()

    @pytest.mark.asyncio
    async def test_acquire_immediate(self):
        bucket = TokenBucket(RateLimiterConfig(tokens_per_minute=1_000_000))
        wait = await bucket.acquire(100)
        assert wait < 0.1

    @pytest.mark.asyncio
    async def test_acquire_consumes_tokens(self):
        bucket = TokenBucket(RateLimiterConfig(tokens_per_minute=1000))
        initial = bucket.available_tokens
        await bucket.acquire(500)
        assert bucket.available_tokens < initial

    @pytest.mark.asyncio
    async def test_disabled_returns_zero(self):
        bucket = TokenBucket(RateLimiterConfig(enabled=False))
        wait = await bucket.acquire(999_999)
        assert wait == 0.0

    @pytest.mark.asyncio
    async def test_adaptive_reduction(self):
        bucket = TokenBucket(RateLimiterConfig(tokens_per_minute=100_000))
        original = bucket.current_tokens_per_minute
        await bucket.record_rate_limit()
        assert bucket.current_tokens_per_minute < original

    @pytest.mark.asyncio
    async def test_adaptive_floor(self):
        cfg = RateLimiterConfig(tokens_per_minute=10_000, reduction_factor=0.1)
        bucket = TokenBucket(cfg)
        for _ in range(20):
            await bucket.record_rate_limit()
        # Should not go below 25% of base
        assert bucket.current_tokens_per_minute >= 2500

    @pytest.mark.asyncio
    async def test_record_success_increments(self):
        bucket = TokenBucket()
        await bucket.record_rate_limit()
        assert bucket._successes_since_limit == 0
        await bucket.record_success()
        assert bucket._successes_since_limit == 1

    @pytest.mark.asyncio
    async def test_timeout_on_large_request(self):
        cfg = RateLimiterConfig(tokens_per_minute=100, max_wait_seconds=0.5)
        bucket = TokenBucket(cfg)
        # Drain tokens
        bucket._tokens = 0
        with pytest.raises(asyncio.TimeoutError, match="waited"):
            await bucket.acquire(99999)

    def test_global_singleton(self):
        reset_global_rate_limiter()
        a = get_global_rate_limiter()
        b = get_global_rate_limiter()
        assert a is b

    def test_global_reset(self):
        a = get_global_rate_limiter()
        reset_global_rate_limiter()
        b = get_global_rate_limiter()
        assert a is not b


# ---------------------------------------------------------------------------
# Factory Tests
# ---------------------------------------------------------------------------


class TestFactory:
    def test_create_mock(self):
        client = create_llm_client(client_type="mock")
        assert isinstance(client, MockLLMClient)

    def test_invalid_type_raises(self):
        with pytest.raises(ValueError, match="Unknown LLM client type"):
            create_llm_client(client_type="nonexistent")

    def test_env_var_override(self, monkeypatch):
        monkeypatch.setenv("LLM_CLIENT_TYPE", "mock")
        client = create_llm_client()
        assert isinstance(client, MockLLMClient)

    def test_groq_type_without_key(self, monkeypatch, tmp_path):
        monkeypatch.delenv("GROQ_API_KEY", raising=False)
        monkeypatch.setattr(Path, "home", lambda: tmp_path)
        with pytest.raises((LLMAuthenticationError, LLMError)):
            create_llm_client(client_type="groq")

    def test_anthropic_type_without_key(self, monkeypatch, tmp_path):
        monkeypatch.delenv("ANTHROPIC_API_KEY", raising=False)
        monkeypatch.setattr(Path, "home", lambda: tmp_path)
        with pytest.raises((LLMAuthenticationError, LLMError)):
            create_llm_client(client_type="anthropic")

    def test_model_env_override(self, monkeypatch):
        monkeypatch.setenv("LLM_DEFAULT_MODEL", "custom-model")
        client = create_llm_client(client_type="mock")
        assert client.default_model == "custom-model"


# ---------------------------------------------------------------------------
# Mock Client Tests
# ---------------------------------------------------------------------------


class TestMockClient:
    @pytest.mark.asyncio
    async def test_query_returns_response(self):
        client = MockLLMClient(responses=["hello"])
        resp = await client.query("test")
        assert resp.content == "hello"
        assert isinstance(resp, LLMResponse)

    @pytest.mark.asyncio
    async def test_query_cycles_responses(self):
        client = MockLLMClient(responses=["a", "b"])
        r1 = await client.query("q1")
        r2 = await client.query("q2")
        r3 = await client.query("q3")
        assert r1.content == "a"
        assert r2.content == "b"
        assert r3.content == "a"

    @pytest.mark.asyncio
    async def test_call_history(self):
        client = MockLLMClient()
        await client.query("prompt1", system_prompt="sys1")
        assert client.call_count == 1
        assert client.call_history[0]["prompt"] == "prompt1"


# ---------------------------------------------------------------------------
# Groq Client Tests (mocked SDK)
# ---------------------------------------------------------------------------


class TestGroqClient:
    @pytest.fixture(autouse=True)
    def _reset_limiter(self):
        reset_global_rate_limiter()
        yield
        reset_global_rate_limiter()

    def test_load_key_from_env(self, monkeypatch, tmp_path):
        monkeypatch.setattr(Path, "home", lambda: tmp_path)
        monkeypatch.setenv("GROQ_API_KEY", "test-key-123")
        with patch("groq.AsyncGroq") as mock_cls:
            mock_cls.return_value = MagicMock()
            from sw4rm.llm.groq import GroqClient
            client = GroqClient()
            assert client.api_key == "test-key-123"

    def test_load_key_from_file(self, monkeypatch, tmp_path):
        monkeypatch.delenv("GROQ_API_KEY", raising=False)
        monkeypatch.setattr(Path, "home", lambda: tmp_path)
        key_file = tmp_path / ".groq"
        key_file.write_text("file-key-456\n")
        with patch("groq.AsyncGroq") as mock_cls:
            mock_cls.return_value = MagicMock()
            from sw4rm.llm.groq import GroqClient
            client = GroqClient()
            assert client.api_key == "file-key-456"

    def test_no_key_raises(self, monkeypatch, tmp_path):
        monkeypatch.delenv("GROQ_API_KEY", raising=False)
        monkeypatch.setattr(Path, "home", lambda: tmp_path)
        from sw4rm.llm.groq import GroqClient
        with pytest.raises(LLMAuthenticationError, match="No Groq API key"):
            GroqClient()

    @pytest.mark.asyncio
    async def test_query_success(self, monkeypatch, tmp_path):
        monkeypatch.setenv("GROQ_API_KEY", "test-key")
        monkeypatch.setattr(Path, "home", lambda: tmp_path)

        mock_response = MagicMock()
        mock_response.choices = [MagicMock()]
        mock_response.choices[0].message.content = "Hello world"
        mock_response.model = "llama-3.3-70b-versatile"
        mock_response.usage = MagicMock()
        mock_response.usage.prompt_tokens = 10
        mock_response.usage.completion_tokens = 5

        mock_client = AsyncMock()
        mock_client.chat.completions.create = AsyncMock(return_value=mock_response)

        with patch("groq.AsyncGroq", return_value=mock_client):
            from sw4rm.llm.groq import GroqClient
            client = GroqClient()
            resp = await client.query("test prompt", system_prompt="be helpful")

        assert resp.content == "Hello world"
        assert resp.usage["input_tokens"] == 10
        assert resp.usage["output_tokens"] == 5

        # Verify the API was called with correct params
        call_kwargs = mock_client.chat.completions.create.call_args
        messages = call_kwargs.kwargs["messages"]
        assert messages[0]["role"] == "system"
        assert messages[1]["role"] == "user"

    @pytest.mark.asyncio
    async def test_query_model_override(self, monkeypatch, tmp_path):
        monkeypatch.setenv("GROQ_API_KEY", "test-key")
        monkeypatch.setattr(Path, "home", lambda: tmp_path)

        mock_response = MagicMock()
        mock_response.choices = [MagicMock()]
        mock_response.choices[0].message.content = "ok"
        mock_response.model = "mixtral-8x7b-32768"
        mock_response.usage = None

        mock_client = AsyncMock()
        mock_client.chat.completions.create = AsyncMock(return_value=mock_response)

        with patch("groq.AsyncGroq", return_value=mock_client):
            from sw4rm.llm.groq import GroqClient
            client = GroqClient()
            await client.query("test", model="mixtral-8x7b-32768")

        call_kwargs = mock_client.chat.completions.create.call_args.kwargs
        assert call_kwargs["model"] == "mixtral-8x7b-32768"

    @pytest.mark.asyncio
    async def test_api_error_wrapped(self, monkeypatch, tmp_path):
        monkeypatch.setenv("GROQ_API_KEY", "test-key")
        monkeypatch.setattr(Path, "home", lambda: tmp_path)

        mock_client = AsyncMock()
        mock_client.chat.completions.create = AsyncMock(
            side_effect=RuntimeError("connection failed")
        )

        with patch("groq.AsyncGroq", return_value=mock_client):
            from sw4rm.llm.groq import GroqClient
            client = GroqClient()
            with pytest.raises(LLMError, match="Groq API error"):
                await client.query("test")


# ---------------------------------------------------------------------------
# Anthropic Client Tests (mocked SDK)
# ---------------------------------------------------------------------------


class TestAnthropicClient:
    @pytest.fixture(autouse=True)
    def _reset_limiter(self):
        reset_global_rate_limiter()
        yield
        reset_global_rate_limiter()

    def test_load_key_from_env(self, monkeypatch, tmp_path):
        monkeypatch.setattr(Path, "home", lambda: tmp_path)
        monkeypatch.setenv("ANTHROPIC_API_KEY", "sk-ant-test-123")

        mock_anthropic = MagicMock()
        mock_anthropic.AsyncAnthropic.return_value = MagicMock()

        with patch.dict("sys.modules", {"anthropic": mock_anthropic}):
            from sw4rm.llm.anthropic import AnthropicClient
            client = AnthropicClient()
            assert client.api_key == "sk-ant-test-123"

    def test_load_key_from_file(self, monkeypatch, tmp_path):
        monkeypatch.delenv("ANTHROPIC_API_KEY", raising=False)
        monkeypatch.setattr(Path, "home", lambda: tmp_path)
        key_file = tmp_path / ".anthropic"
        key_file.write_text("sk-ant-file-456\n")

        mock_anthropic = MagicMock()
        mock_anthropic.AsyncAnthropic.return_value = MagicMock()

        with patch.dict("sys.modules", {"anthropic": mock_anthropic}):
            from sw4rm.llm.anthropic import AnthropicClient
            client = AnthropicClient()
            assert client.api_key == "sk-ant-file-456"

    def test_no_key_raises(self, monkeypatch, tmp_path):
        monkeypatch.delenv("ANTHROPIC_API_KEY", raising=False)
        monkeypatch.setattr(Path, "home", lambda: tmp_path)

        mock_anthropic = MagicMock()
        with patch.dict("sys.modules", {"anthropic": mock_anthropic}):
            from sw4rm.llm.anthropic import AnthropicClient
            with pytest.raises(LLMAuthenticationError, match="No Anthropic API key"):
                AnthropicClient()

    @pytest.mark.asyncio
    async def test_query_success(self, monkeypatch, tmp_path):
        monkeypatch.setenv("ANTHROPIC_API_KEY", "sk-ant-test")
        monkeypatch.setattr(Path, "home", lambda: tmp_path)

        # Build a mock response with content blocks
        mock_block = MagicMock()
        mock_block.type = "text"
        mock_block.text = "Claude says hello"

        mock_usage = MagicMock()
        mock_usage.input_tokens = 15
        mock_usage.output_tokens = 8

        mock_response = MagicMock()
        mock_response.content = [mock_block]
        mock_response.model = "claude-sonnet-4-20250514"
        mock_response.usage = mock_usage

        mock_client_instance = AsyncMock()
        mock_client_instance.messages.create = AsyncMock(return_value=mock_response)

        mock_anthropic = MagicMock()
        mock_anthropic.AsyncAnthropic.return_value = mock_client_instance

        with patch.dict("sys.modules", {"anthropic": mock_anthropic}):
            from sw4rm.llm.anthropic import AnthropicClient
            client = AnthropicClient()
            resp = await client.query("test prompt", system_prompt="be helpful")

        assert resp.content == "Claude says hello"
        assert resp.usage["input_tokens"] == 15
        assert resp.usage["output_tokens"] == 8

        # Verify system prompt was passed as top-level param
        call_kwargs = mock_client_instance.messages.create.call_args.kwargs
        assert call_kwargs["system"] == "be helpful"
        assert call_kwargs["messages"][0]["role"] == "user"

    @pytest.mark.asyncio
    async def test_query_model_override(self, monkeypatch, tmp_path):
        monkeypatch.setenv("ANTHROPIC_API_KEY", "sk-ant-test")
        monkeypatch.setattr(Path, "home", lambda: tmp_path)

        mock_block = MagicMock()
        mock_block.type = "text"
        mock_block.text = "ok"

        mock_response = MagicMock()
        mock_response.content = [mock_block]
        mock_response.model = "claude-opus-4-20250514"
        mock_response.usage = MagicMock(input_tokens=5, output_tokens=1)

        mock_client_instance = AsyncMock()
        mock_client_instance.messages.create = AsyncMock(return_value=mock_response)

        mock_anthropic = MagicMock()
        mock_anthropic.AsyncAnthropic.return_value = mock_client_instance

        with patch.dict("sys.modules", {"anthropic": mock_anthropic}):
            from sw4rm.llm.anthropic import AnthropicClient
            client = AnthropicClient()
            await client.query("test", model="claude-opus-4-20250514")

        call_kwargs = mock_client_instance.messages.create.call_args.kwargs
        assert call_kwargs["model"] == "claude-opus-4-20250514"


# ---------------------------------------------------------------------------
# Integration-level: module imports
# ---------------------------------------------------------------------------


class TestModuleImports:
    def test_all_exports(self):
        import sw4rm.llm as llm
        for name in [
            "LLMClient", "LLMResponse", "LLMError", "LLMAuthenticationError",
            "LLMRateLimitError", "LLMTimeoutError", "LLMContextLengthError",
            "create_llm_client", "MockLLMClient",
            "RateLimiterConfig", "TokenBucket",
            "get_global_rate_limiter", "reset_global_rate_limiter",
        ]:
            assert hasattr(llm, name), f"Missing export: {name}"

    def test_lazy_groq_import(self):
        from sw4rm.llm import GroqClient
        assert GroqClient.__name__ == "GroqClient"

    def test_lazy_anthropic_import(self):
        from sw4rm.llm import AnthropicClient
        assert AnthropicClient.__name__ == "AnthropicClient"

    def test_lazy_import_error(self):
        import sw4rm.llm as llm
        with pytest.raises(AttributeError):
            _ = llm.NonexistentClient
