/**
 * Mock LLM client for testing.
 *
 * Provides deterministic responses without making actual API calls.
 * Cycles through a canned response array and records call history.
 *
 * @module llm/mock
 */

import type { LlmClient, LlmResponse, QueryOptions } from './client.js';

/** A recorded call entry from the mock client. */
export interface MockCallRecord {
  prompt: string;
  systemPrompt?: string;
  maxTokens: number;
  temperature: number;
  model: string;
}

/**
 * Mock LLM client for testing without API calls.
 *
 * Returns configurable responses for testing purposes. If no responses are
 * provided, returns a default echo of the prompt.
 *
 * @example
 * ```typescript
 * import { MockLlmClient } from '@sw4rm/js-sdk';
 *
 * // Simple usage -- returns echo of prompt
 * const client = new MockLlmClient();
 * const response = await client.query('Hello');
 * console.log(response.content); // "Mock response to: Hello"
 *
 * // Custom responses (cycles)
 * const client2 = new MockLlmClient({
 *   responses: ['First response', 'Second response'],
 * });
 *
 * // Custom response generator
 * const client3 = new MockLlmClient({
 *   responseGenerator: (prompt) => `Processed: ${prompt}`,
 * });
 * ```
 */
export class MockLlmClient implements LlmClient {
  /** The model name returned in responses. */
  readonly defaultModel: string;

  private readonly responses: string[];
  private responseIndex = 0;
  private readonly responseGenerator:
    | ((prompt: string) => string)
    | undefined;
  private _callCount = 0;
  private readonly _callHistory: MockCallRecord[] = [];

  constructor(opts?: {
    /** Model name to return in responses. */
    defaultModel?: string;
    /** List of responses to return in order (cycles when exhausted). */
    responses?: string[];
    /** Function to generate responses from prompts. */
    responseGenerator?: (prompt: string) => string;
  }) {
    this.defaultModel = opts?.defaultModel ?? 'mock-model';
    this.responses = opts?.responses ?? [];
    this.responseGenerator = opts?.responseGenerator;
  }

  /** Number of queries made to this client. */
  get callCount(): number {
    return this._callCount;
  }

  /** History of all calls made to this client. */
  get callHistory(): readonly MockCallRecord[] {
    return this._callHistory;
  }

  /** Reset call count, history, and response index. */
  reset(): void {
    this._callCount = 0;
    this._callHistory.length = 0;
    this.responseIndex = 0;
  }

  /**
   * Return a mock response.
   *
   * Priority for determining response content:
   *   1. `responseGenerator` function (if provided)
   *   2. `responses` array (cycles through entries)
   *   3. Default echo: "Mock response to: <prompt>"
   *
   * @param prompt - The prompt (recorded in history).
   * @param opts   - Optional query configuration (recorded in history).
   * @returns LlmResponse with mock content.
   */
  async query(prompt: string, opts?: QueryOptions): Promise<LlmResponse> {
    const model = opts?.model ?? this.defaultModel;
    const maxTokens = opts?.maxTokens ?? 4096;
    const temperature = opts?.temperature ?? 1.0;

    this._callCount += 1;
    this._callHistory.push({
      prompt,
      systemPrompt: opts?.systemPrompt,
      maxTokens,
      temperature,
      model,
    });

    let content: string;
    if (this.responseGenerator) {
      content = this.responseGenerator(prompt);
    } else if (this.responses.length > 0) {
      content = this.responses[this.responseIndex % this.responses.length]!;
      this.responseIndex += 1;
    } else {
      content = `Mock response to: ${prompt.slice(0, 100)}`;
    }

    return {
      content,
      model,
      usage: {
        input_tokens: Math.max(Math.floor(prompt.length / 4), 1),
        output_tokens: Math.max(Math.floor(content.length / 4), 1),
      },
      metadata: { mock: true, call_count: this._callCount },
    };
  }

  /**
   * Stream a mock response.
   *
   * Yields the response word by word to simulate streaming.
   *
   * @param prompt - The prompt (recorded in history).
   * @param opts   - Optional query configuration.
   * @yields Words from the mock response.
   */
  async *streamQuery(
    prompt: string,
    opts?: QueryOptions,
  ): AsyncGenerator<string> {
    const response = await this.query(prompt, opts);
    const words = response.content.split(' ');
    for (let i = 0; i < words.length; i++) {
      yield words[i]! + (i < words.length - 1 ? ' ' : '');
    }
  }
}
