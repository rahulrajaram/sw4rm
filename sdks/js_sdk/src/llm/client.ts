/**
 * Abstract LLM client interface.
 *
 * This module provides the base interface for LLM clients used by SW4RM agents.
 * Implementations can use Anthropic API directly, Groq API, or mock clients
 * for testing.
 *
 * @module llm/client
 */

// ---------------------------------------------------------------------------
// Response type
// ---------------------------------------------------------------------------

/** Response from an LLM API call. */
export interface LlmResponse {
  /** The generated text content. */
  content: string;
  /** The model that generated the response. */
  model: string;
  /** Token usage statistics (if available). */
  usage?: { input_tokens: number; output_tokens: number };
  /** Additional response metadata. */
  metadata?: Record<string, unknown>;
}

// ---------------------------------------------------------------------------
// Query options
// ---------------------------------------------------------------------------

/** Options for LLM query calls. */
export interface QueryOptions {
  /** Optional system prompt for context. */
  systemPrompt?: string;
  /** Maximum tokens to generate (default 4096). */
  maxTokens?: number;
  /** Sampling temperature 0.0-2.0 (default 1.0). */
  temperature?: number;
  /** Override the default model. */
  model?: string;
}

// ---------------------------------------------------------------------------
// Client interface
// ---------------------------------------------------------------------------

/**
 * Abstract interface for LLM clients.
 *
 * All LLM client implementations must implement this interface.
 * This allows SW4RM agents to be provider-agnostic.
 *
 * Implementations:
 *   - GroqClient:      Uses Groq API directly (API key)
 *   - AnthropicClient: Uses Anthropic API directly (API key)
 *   - MockLlmClient:   For testing without API calls
 */
export interface LlmClient {
  /**
   * Send a query to the LLM and get a complete response.
   *
   * @param prompt - The user prompt/query to send.
   * @param opts   - Optional query configuration.
   * @returns LlmResponse with the generated content and metadata.
   * @throws LlmError on API errors or failures.
   * @throws LlmAuthenticationError on authentication failures.
   * @throws LlmRateLimitError when rate limits are exceeded.
   * @throws LlmTimeoutError when the request times out.
   */
  query(prompt: string, opts?: QueryOptions): Promise<LlmResponse>;

  /**
   * Stream a query response chunk by chunk.
   *
   * @param prompt - The user prompt/query to send.
   * @param opts   - Optional query configuration.
   * @yields Text chunks as they arrive from the API.
   * @throws LlmError on API errors or failures.
   */
  streamQuery(prompt: string, opts?: QueryOptions): AsyncGenerator<string>;
}

// ---------------------------------------------------------------------------
// Exception hierarchy
// ---------------------------------------------------------------------------

/** Base exception for all LLM client errors. */
export class LlmError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'LlmError';
    Object.setPrototypeOf(this, new.target.prototype);
  }
}

/**
 * Raised when API authentication fails.
 *
 * Common causes:
 *   - Invalid API key
 *   - Expired credentials
 *   - Missing credentials
 */
export class LlmAuthenticationError extends LlmError {
  constructor(message: string) {
    super(message);
    this.name = 'LlmAuthenticationError';
  }
}

/**
 * Raised when API rate limits are exceeded.
 *
 * The caller should implement exponential backoff when handling this.
 */
export class LlmRateLimitError extends LlmError {
  constructor(message: string) {
    super(message);
    this.name = 'LlmRateLimitError';
  }
}

/**
 * Raised when an API request times out.
 *
 * Consider increasing the timeout or simplifying the prompt.
 */
export class LlmTimeoutError extends LlmError {
  constructor(message: string) {
    super(message);
    this.name = 'LlmTimeoutError';
  }
}

/**
 * Raised when the prompt exceeds the model's context length.
 *
 * Consider truncating the prompt or using a model with larger context.
 */
export class LlmContextLengthError extends LlmError {
  constructor(message: string) {
    super(message);
    this.name = 'LlmContextLengthError';
  }
}
