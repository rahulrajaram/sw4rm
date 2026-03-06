/**
 * SW4RM LLM -- LLM client abstraction for SW4RM agents.
 *
 * This module provides a unified interface for LLM interactions, supporting:
 *   - Groq API (API key from ~/.groq or GROQ_API_KEY)
 *   - Anthropic API (API key from ~/.anthropic or ANTHROPIC_API_KEY)
 *   - Mock client for testing
 *
 * Usage:
 * ```typescript
 * import { createLlmClient } from '@sw4rm/js-sdk';
 *
 * // Create client via environment (LLM_CLIENT_TYPE=groq|anthropic|mock)
 * const client = createLlmClient();
 *
 * // Or explicitly
 * const client = createLlmClient({ clientType: 'groq' });
 *
 * // Query the LLM
 * const response = await client.query(
 *   'Analyze this task and suggest next steps',
 *   { systemPrompt: 'You are a helpful task analysis agent.' },
 * );
 * console.log(response.content);
 *
 * // Stream responses
 * for await (const chunk of client.streamQuery('Generate a report')) {
 *   process.stdout.write(chunk);
 * }
 * ```
 *
 * @module llm
 */

// client.ts -- Interface and exceptions
export type { LlmClient, LlmResponse, QueryOptions } from './client.js';
export {
  LlmError,
  LlmAuthenticationError,
  LlmRateLimitError,
  LlmTimeoutError,
  LlmContextLengthError,
} from './client.js';

// rateLimiter.ts
export type { RateLimiterConfig } from './rateLimiter.js';
export {
  buildRateLimiterConfig,
  TokenBucket,
  getGlobalRateLimiter,
  resetGlobalRateLimiter,
} from './rateLimiter.js';

// mock.ts
export { MockLlmClient } from './mock.js';
export type { MockCallRecord } from './mock.js';

// groq.ts
export { GroqClient } from './groq.js';
export type { GroqClientOptions } from './groq.js';

// anthropic.ts
export { AnthropicClient } from './anthropic.js';
export type { AnthropicClientOptions } from './anthropic.js';

// factory.ts
export { createLlmClient } from './factory.js';
export type { CreateLlmClientOptions } from './factory.js';
