/**
 * Factory for creating LLM clients.
 *
 * Provides a simple way to create the appropriate LLM client based on
 * environment configuration or explicit parameters.
 *
 * @module llm/factory
 */

import type { LlmClient } from './client.js';
import { MockLlmClient } from './mock.js';
import { GroqClient } from './groq.js';
import { AnthropicClient } from './anthropic.js';

/** Options for the LLM client factory. */
export interface CreateLlmClientOptions {
  /**
   * The type of client to create.
   *
   * Valid types: "groq", "anthropic", "mock".
   *
   * If not specified, reads from the `LLM_CLIENT_TYPE` environment variable.
   * Defaults to "mock" if neither is set.
   */
  clientType?: string;

  /**
   * Default model to use for queries.
   *
   * If not specified, reads from the `LLM_DEFAULT_MODEL` environment variable.
   * Falls back to each provider's default model.
   */
  model?: string;

  /** API key override (passed to the provider constructor). */
  apiKey?: string;

  /** Request timeout in milliseconds (passed to the provider constructor). */
  timeoutMs?: number;
}

/**
 * Create an LLM client based on environment or explicit type.
 *
 * Resolution order for client type:
 *   1. Explicit `clientType` option
 *   2. `LLM_CLIENT_TYPE` environment variable
 *   3. Default: "mock"
 *
 * Environment variables:
 *   - `LLM_CLIENT_TYPE`: "groq", "anthropic", or "mock" (default: "mock")
 *   - `LLM_DEFAULT_MODEL`: Default model override
 *
 * @param opts - Optional factory configuration.
 * @returns An LlmClient instance of the requested type.
 * @throws Error if an invalid client type is specified.
 *
 * @example
 * ```typescript
 * import { createLlmClient } from '@sw4rm/js-sdk';
 *
 * // Auto-detect from env (default: mock)
 * const client = createLlmClient();
 *
 * // Explicit Groq client
 * const groq = createLlmClient({ clientType: 'groq' });
 *
 * // Mock client for testing
 * const mock = createLlmClient({ clientType: 'mock' });
 *
 * // Anthropic client with model override
 * const claude = createLlmClient({
 *   clientType: 'anthropic',
 *   model: 'claude-sonnet-4-20250514',
 * });
 * ```
 */
export function createLlmClient(opts?: CreateLlmClientOptions): LlmClient {
  const clientType = (
    opts?.clientType ??
    process.env['LLM_CLIENT_TYPE'] ??
    'mock'
  ).toLowerCase();

  const model = opts?.model ?? process.env['LLM_DEFAULT_MODEL'];

  if (clientType === 'mock') {
    return new MockLlmClient({
      defaultModel: model ?? 'mock-model',
    });
  }

  if (clientType === 'groq') {
    return new GroqClient({
      apiKey: opts?.apiKey,
      defaultModel: model,
      timeoutMs: opts?.timeoutMs,
    });
  }

  if (clientType === 'anthropic') {
    return new AnthropicClient({
      apiKey: opts?.apiKey,
      defaultModel: model,
      timeoutMs: opts?.timeoutMs,
    });
  }

  throw new Error(
    `Unknown LLM client type: "${clientType}". ` +
      `Valid types: "groq", "anthropic", "mock"`,
  );
}
