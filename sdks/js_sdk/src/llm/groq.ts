/**
 * Groq LLM client for SW4RM agents.
 *
 * Thin wrapper around the Groq REST API using native `fetch()`.
 * No tool-calling or diagnostic mode -- just prompt in, text out,
 * with rate limiting.
 *
 * Credentials (in order):
 *   1. `apiKey` constructor parameter
 *   2. `GROQ_API_KEY` environment variable
 *   3. `~/.groq` file (plain text, one line)
 *
 * @module llm/groq
 */

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

import type { LlmClient, LlmResponse, QueryOptions } from './client.js';
import {
  LlmAuthenticationError,
  LlmContextLengthError,
  LlmError,
  LlmRateLimitError,
  LlmTimeoutError,
} from './client.js';
import { getGlobalRateLimiter } from './rateLimiter.js';
import type { TokenBucket } from './rateLimiter.js';

const DEFAULT_MODEL = 'llama-3.3-70b-versatile';
const BASE_URL = 'https://api.groq.com/openai/v1/chat/completions';

/** Options for constructing a GroqClient. */
export interface GroqClientOptions {
  /** API key override (takes precedence over env / dotfile). */
  apiKey?: string;
  /** Default model to use for queries. */
  defaultModel?: string;
  /** Request timeout in milliseconds. */
  timeoutMs?: number;
}

/**
 * LLM client for the Groq API (OpenAI-compatible chat completions).
 *
 * Credentials are resolved from (in order):
 *   1. `apiKey` constructor option
 *   2. `GROQ_API_KEY` environment variable
 *   3. `~/.groq` file (plain text, one line)
 *
 * Environment variables:
 *   - `GROQ_API_KEY`: API key override
 *   - `GROQ_DEFAULT_MODEL`: Default model override
 */
export class GroqClient implements LlmClient {
  /** The resolved API key. */
  readonly apiKey: string;
  /** The default model used when none is specified per-call. */
  readonly defaultModel: string;

  private readonly timeoutMs: number;
  private readonly rateLimiter: TokenBucket;

  constructor(opts?: GroqClientOptions) {
    this.defaultModel =
      opts?.defaultModel ??
      process.env['GROQ_DEFAULT_MODEL'] ??
      DEFAULT_MODEL;

    const envKey = process.env['GROQ_API_KEY']?.trim();
    const resolved = opts?.apiKey ?? envKey ?? GroqClient.loadKeyFile();

    if (!resolved) {
      throw new LlmAuthenticationError(
        'No Groq API key. Set GROQ_API_KEY, pass apiKey, or create ~/.groq',
      );
    }
    this.apiKey = resolved;
    this.timeoutMs = opts?.timeoutMs ?? 120_000;
    this.rateLimiter = getGlobalRateLimiter();
  }

  /**
   * Load API key from ~/.groq file.
   *
   * @returns The key string, or null if the file does not exist.
   */
  static loadKeyFile(): string | null {
    try {
      const keyPath = path.join(os.homedir(), '.groq');
      if (fs.existsSync(keyPath)) {
        return fs.readFileSync(keyPath, 'utf-8').trim();
      }
    } catch {
      // Silently ignore filesystem errors
    }
    return null;
  }

  // -- Helpers -------------------------------------------------------------

  private estimateTokens(
    prompt: string,
    systemPrompt?: string,
  ): number {
    let total = prompt.length;
    if (systemPrompt) total += systemPrompt.length;
    return Math.max(Math.floor(total / 4), 100);
  }

  private buildMessages(
    prompt: string,
    systemPrompt?: string,
  ): Array<{ role: string; content: string }> {
    const messages: Array<{ role: string; content: string }> = [];
    if (systemPrompt) {
      messages.push({ role: 'system', content: systemPrompt });
    }
    messages.push({ role: 'user', content: prompt });
    return messages;
  }

  /**
   * Map an HTTP error response to the appropriate LlmError subclass.
   *
   * @param status  - HTTP status code.
   * @param body    - Parsed response body (if available).
   * @param message - Raw error message.
   */
  private mapError(
    status: number,
    body: Record<string, unknown> | null,
    message: string,
  ): LlmError {
    if (status === 401 || status === 403) {
      return new LlmAuthenticationError(`Groq auth failed (${status}): ${message}`);
    }
    if (status === 429) {
      this.rateLimiter.recordRateLimit();
      return new LlmRateLimitError(`Groq rate limit exceeded: ${message}`);
    }
    if (status === 408 || status === 504) {
      return new LlmTimeoutError(`Groq request timed out (${status}): ${message}`);
    }
    // Groq uses OpenAI error codes -- check for context_length_exceeded
    const errorObj = body?.['error'] as Record<string, unknown> | undefined;
    const code = errorObj?.['code'];
    if (code === 'context_length_exceeded') {
      return new LlmContextLengthError(`Groq context length exceeded: ${message}`);
    }
    return new LlmError(`Groq API error (${status}): ${message}`);
  }

  // -- Public API ----------------------------------------------------------

  /**
   * Send a query to Groq and get a complete response.
   *
   * @param prompt - The user prompt/query.
   * @param opts   - Optional query configuration.
   * @returns LlmResponse with generated content and metadata.
   */
  async query(prompt: string, opts?: QueryOptions): Promise<LlmResponse> {
    const useModel = opts?.model ?? this.defaultModel;
    const maxTokens = opts?.maxTokens ?? 4096;
    const temperature = opts?.temperature ?? 1.0;
    const systemPrompt = opts?.systemPrompt;

    const estimated = this.estimateTokens(prompt, systemPrompt);
    await this.rateLimiter.acquire(estimated);

    const body = {
      model: useModel,
      messages: this.buildMessages(prompt, systemPrompt),
      max_tokens: maxTokens,
      temperature,
    };

    let response: Response;
    try {
      const controller = new AbortController();
      const timer = setTimeout(() => controller.abort(), this.timeoutMs);
      response = await fetch(BASE_URL, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${this.apiKey}`,
        },
        body: JSON.stringify(body),
        signal: controller.signal,
      });
      clearTimeout(timer);
    } catch (err: unknown) {
      if (err instanceof Error && err.name === 'AbortError') {
        throw new LlmTimeoutError(`Groq request timed out after ${this.timeoutMs}ms`);
      }
      throw new LlmError(`Groq network error: ${String(err)}`);
    }

    if (!response.ok) {
      let errorBody: Record<string, unknown> | null = null;
      let errorMessage = response.statusText;
      try {
        errorBody = (await response.json()) as Record<string, unknown>;
        const errorObj = errorBody?.['error'] as Record<string, unknown> | undefined;
        errorMessage = (errorObj?.['message'] as string) ?? errorMessage;
      } catch {
        // Could not parse error body
      }
      throw this.mapError(response.status, errorBody, errorMessage);
    }

    const data = (await response.json()) as Record<string, unknown>;
    this.rateLimiter.recordSuccess();

    // Parse OpenAI-compatible response
    const choices = data['choices'] as Array<Record<string, unknown>> | undefined;
    const firstChoice = choices?.[0];
    const messageObj = firstChoice?.['message'] as Record<string, unknown> | undefined;
    const content = (messageObj?.['content'] as string) ?? '';

    const usageObj = data['usage'] as Record<string, unknown> | undefined;
    let usage: { input_tokens: number; output_tokens: number } | undefined;
    if (usageObj) {
      usage = {
        input_tokens: (usageObj['prompt_tokens'] as number) ?? 0,
        output_tokens: (usageObj['completion_tokens'] as number) ?? 0,
      };
    }

    return {
      content,
      model: (data['model'] as string) ?? useModel,
      usage,
    };
  }

  /**
   * Stream a query response chunk by chunk.
   *
   * Uses Server-Sent Events (SSE) streaming from the Groq API.
   *
   * @param prompt - The user prompt/query.
   * @param opts   - Optional query configuration.
   * @yields Text chunks as they arrive from the API.
   */
  async *streamQuery(prompt: string, opts?: QueryOptions): AsyncGenerator<string> {
    const useModel = opts?.model ?? this.defaultModel;
    const maxTokens = opts?.maxTokens ?? 4096;
    const temperature = opts?.temperature ?? 1.0;
    const systemPrompt = opts?.systemPrompt;

    const estimated = this.estimateTokens(prompt, systemPrompt);
    await this.rateLimiter.acquire(estimated);

    const body = {
      model: useModel,
      messages: this.buildMessages(prompt, systemPrompt),
      max_tokens: maxTokens,
      temperature,
      stream: true,
    };

    let response: Response;
    try {
      const controller = new AbortController();
      const timer = setTimeout(() => controller.abort(), this.timeoutMs);
      response = await fetch(BASE_URL, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${this.apiKey}`,
        },
        body: JSON.stringify(body),
        signal: controller.signal,
      });
      clearTimeout(timer);
    } catch (err: unknown) {
      if (err instanceof Error && err.name === 'AbortError') {
        throw new LlmTimeoutError(`Groq request timed out after ${this.timeoutMs}ms`);
      }
      throw new LlmError(`Groq network error: ${String(err)}`);
    }

    if (!response.ok) {
      let errorBody: Record<string, unknown> | null = null;
      let errorMessage = response.statusText;
      try {
        errorBody = (await response.json()) as Record<string, unknown>;
        const errorObj = errorBody?.['error'] as Record<string, unknown> | undefined;
        errorMessage = (errorObj?.['message'] as string) ?? errorMessage;
      } catch {
        // Could not parse error body
      }
      throw this.mapError(response.status, errorBody, errorMessage);
    }

    if (!response.body) {
      throw new LlmError('Groq streaming response has no body');
    }

    const reader = response.body.getReader();
    const decoder = new TextDecoder();
    let buffer = '';
    let streamCompleted = false;

    try {
      for (;;) {
        const { done, value } = await reader.read();
        if (done) break;

        buffer += decoder.decode(value, { stream: true });
        const lines = buffer.split('\n');
        buffer = lines.pop() ?? '';

        for (const line of lines) {
          const trimmed = line.trim();
          if (!trimmed || !trimmed.startsWith('data: ')) continue;
          const payload = trimmed.slice(6);
          if (payload === '[DONE]') {
            streamCompleted = true;
            return;
          }

          try {
            const chunk = JSON.parse(payload) as Record<string, unknown>;
            const choices = chunk['choices'] as Array<Record<string, unknown>> | undefined;
            const delta = choices?.[0]?.['delta'] as Record<string, unknown> | undefined;
            const content = delta?.['content'] as string | undefined;
            if (content) yield content;
          } catch {
            // Skip malformed SSE chunks
          }
        }
      }
      // Stream ended naturally (reader done without [DONE] sentinel)
      streamCompleted = true;
    } finally {
      reader.releaseLock();
      if (streamCompleted) this.rateLimiter.recordSuccess();
    }
  }
}
