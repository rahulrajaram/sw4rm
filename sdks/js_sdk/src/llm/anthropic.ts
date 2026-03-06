/**
 * Anthropic LLM client for SW4RM agents.
 *
 * Thin wrapper around the Anthropic Messages REST API using native `fetch()`.
 * Handles system-message normalization (Anthropic uses a top-level `system`
 * param, not an in-band system message).
 *
 * Credentials (in order):
 *   1. `apiKey` constructor parameter
 *   2. `ANTHROPIC_API_KEY` environment variable
 *   3. `~/.anthropic` file (plain text, one line)
 *
 * @module llm/anthropic
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

const DEFAULT_MODEL = 'claude-sonnet-4-20250514';
const BASE_URL = 'https://api.anthropic.com/v1/messages';
const ANTHROPIC_VERSION = '2023-06-01';

/** Options for constructing an AnthropicClient. */
export interface AnthropicClientOptions {
  /** API key override (takes precedence over env / dotfile). */
  apiKey?: string;
  /** Default model to use for queries. */
  defaultModel?: string;
  /** Request timeout in milliseconds. */
  timeoutMs?: number;
}

/**
 * LLM client for the Anthropic Messages API.
 *
 * Credentials are resolved from (in order):
 *   1. `apiKey` constructor option
 *   2. `ANTHROPIC_API_KEY` environment variable
 *   3. `~/.anthropic` file (plain text, one line)
 *
 * Environment variables:
 *   - `ANTHROPIC_API_KEY`: API key override
 *   - `ANTHROPIC_DEFAULT_MODEL`: Default model override
 */
export class AnthropicClient implements LlmClient {
  /** The resolved API key. */
  readonly apiKey: string;
  /** The default model used when none is specified per-call. */
  readonly defaultModel: string;

  private readonly timeoutMs: number;
  private readonly rateLimiter: TokenBucket;

  constructor(opts?: AnthropicClientOptions) {
    this.defaultModel =
      opts?.defaultModel ??
      process.env['ANTHROPIC_DEFAULT_MODEL'] ??
      DEFAULT_MODEL;

    const envKey = process.env['ANTHROPIC_API_KEY']?.trim();
    const resolved = opts?.apiKey ?? envKey ?? AnthropicClient.loadKeyFile();

    if (!resolved) {
      throw new LlmAuthenticationError(
        'No Anthropic API key. Set ANTHROPIC_API_KEY, pass apiKey, or create ~/.anthropic',
      );
    }
    this.apiKey = resolved;
    this.timeoutMs = opts?.timeoutMs ?? 300_000;
    this.rateLimiter = getGlobalRateLimiter();
  }

  /**
   * Load API key from ~/.anthropic file.
   *
   * @returns The key string, or null if the file does not exist.
   */
  static loadKeyFile(): string | null {
    try {
      const keyPath = path.join(os.homedir(), '.anthropic');
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
      return new LlmAuthenticationError(
        `Anthropic auth failed (${status}): ${message}`,
      );
    }
    if (status === 429) {
      this.rateLimiter.recordRateLimit();
      return new LlmRateLimitError(
        `Anthropic rate limit exceeded: ${message}`,
      );
    }
    if (status === 408 || status === 504) {
      return new LlmTimeoutError(
        `Anthropic request timed out (${status}): ${message}`,
      );
    }
    // Anthropic error type for context length
    const errorType = body?.['error'] as Record<string, unknown> | undefined;
    const errType = errorType?.['type'] as string | undefined;
    if (errType === 'invalid_request_error') {
      const msg = message.toLowerCase();
      if (msg.includes('context') || msg.includes('token')) {
        return new LlmContextLengthError(
          `Anthropic context length exceeded: ${message}`,
        );
      }
    }
    // Billing / credit errors
    const lowerMsg = message.toLowerCase();
    if (lowerMsg.includes('credit balance') || lowerMsg.includes('billing')) {
      return new LlmAuthenticationError(
        `Anthropic billing error: ${message}`,
      );
    }
    return new LlmError(`Anthropic API error (${status}): ${message}`);
  }

  // -- Public API ----------------------------------------------------------

  /**
   * Send a query to Anthropic and get a complete response.
   *
   * System prompts are sent via the top-level `system` parameter rather
   * than as a system message in the messages array, per the Anthropic API
   * specification.
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

    const requestBody: Record<string, unknown> = {
      model: useModel,
      messages: [{ role: 'user', content: prompt }],
      max_tokens: maxTokens,
      temperature,
    };
    if (systemPrompt) {
      requestBody['system'] = systemPrompt;
    }

    let response: Response;
    try {
      const controller = new AbortController();
      const timer = setTimeout(() => controller.abort(), this.timeoutMs);
      response = await fetch(BASE_URL, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'x-api-key': this.apiKey,
          'anthropic-version': ANTHROPIC_VERSION,
        },
        body: JSON.stringify(requestBody),
        signal: controller.signal,
      });
      clearTimeout(timer);
    } catch (err: unknown) {
      if (err instanceof Error && err.name === 'AbortError') {
        throw new LlmTimeoutError(
          `Anthropic request timed out after ${this.timeoutMs}ms`,
        );
      }
      throw new LlmError(`Anthropic network error: ${String(err)}`);
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

    // Extract text from content blocks
    const contentBlocks = data['content'] as
      | Array<Record<string, unknown>>
      | undefined;
    const textParts: string[] = [];
    if (contentBlocks) {
      for (const block of contentBlocks) {
        if (block['type'] === 'text' && typeof block['text'] === 'string') {
          textParts.push(block['text']);
        }
      }
    }
    const content = textParts.join('').trim();

    const usageObj = data['usage'] as Record<string, unknown> | undefined;
    const inputTokens = (usageObj?.['input_tokens'] as number) ?? 0;
    const outputTokens = (usageObj?.['output_tokens'] as number) ?? 0;

    return {
      content,
      model: (data['model'] as string) ?? useModel,
      usage: {
        input_tokens: inputTokens,
        output_tokens: outputTokens,
      },
    };
  }

  /**
   * Stream a query response chunk by chunk.
   *
   * Uses Server-Sent Events (SSE) streaming from the Anthropic API.
   * System prompts are sent via the top-level `system` parameter.
   *
   * @param prompt - The user prompt/query.
   * @param opts   - Optional query configuration.
   * @yields Text chunks as they arrive from the API.
   */
  async *streamQuery(
    prompt: string,
    opts?: QueryOptions,
  ): AsyncGenerator<string> {
    const useModel = opts?.model ?? this.defaultModel;
    const maxTokens = opts?.maxTokens ?? 4096;
    const temperature = opts?.temperature ?? 1.0;
    const systemPrompt = opts?.systemPrompt;

    const estimated = this.estimateTokens(prompt, systemPrompt);
    await this.rateLimiter.acquire(estimated);

    const requestBody: Record<string, unknown> = {
      model: useModel,
      messages: [{ role: 'user', content: prompt }],
      max_tokens: maxTokens,
      temperature,
      stream: true,
    };
    if (systemPrompt) {
      requestBody['system'] = systemPrompt;
    }

    let response: Response;
    try {
      const controller = new AbortController();
      const timer = setTimeout(() => controller.abort(), this.timeoutMs);
      response = await fetch(BASE_URL, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'x-api-key': this.apiKey,
          'anthropic-version': ANTHROPIC_VERSION,
        },
        body: JSON.stringify(requestBody),
        signal: controller.signal,
      });
      clearTimeout(timer);
    } catch (err: unknown) {
      if (err instanceof Error && err.name === 'AbortError') {
        throw new LlmTimeoutError(
          `Anthropic request timed out after ${this.timeoutMs}ms`,
        );
      }
      throw new LlmError(`Anthropic network error: ${String(err)}`);
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
      throw new LlmError('Anthropic streaming response has no body');
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

          try {
            const event = JSON.parse(payload) as Record<string, unknown>;
            const eventType = event['type'] as string | undefined;

            if (eventType === 'content_block_delta') {
              const delta = event['delta'] as Record<string, unknown> | undefined;
              if (delta?.['type'] === 'text_delta') {
                const text = delta['text'] as string | undefined;
                if (text) yield text;
              }
            } else if (eventType === 'message_stop') {
              streamCompleted = true;
              return;
            }
          } catch {
            // Skip malformed SSE chunks
          }
        }
      }
      // Stream ended naturally (reader done without message_stop event)
      streamCompleted = true;
    } finally {
      reader.releaseLock();
      if (streamCompleted) this.rateLimiter.recordSuccess();
    }
  }
}
