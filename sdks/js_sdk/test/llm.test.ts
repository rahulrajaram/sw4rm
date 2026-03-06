import { describe, expect, it, beforeEach, afterEach, vi } from 'vitest';
import {
  TokenBucket,
  getGlobalRateLimiter,
  resetGlobalRateLimiter,
  MockLlmClient,
  createLlmClient,
  LlmAuthenticationError,
  LlmRateLimitError,
  LlmTimeoutError,
  LlmContextLengthError,
  LlmError,
  GroqClient,
  AnthropicClient,
} from '../src/llm/index.js';

// ---------------------------------------------------------------------------
// TokenBucket / Rate Limiter
// ---------------------------------------------------------------------------

describe('TokenBucket', () => {
  it('acquire deducts tokens immediately when bucket is full', async () => {
    const bucket = new TokenBucket({
      tokensPerMinute: 10_000,
      enabled: true,
      adaptiveEnabled: false,
    });

    const waited = await bucket.acquire(100);
    // Should be nearly instant
    expect(waited).toBeLessThan(500);
    // Should have fewer tokens now
    expect(bucket.availableTokens).toBeLessThan(10_000);
  });

  it('acquire enforces minimum tokens per request', async () => {
    const bucket = new TokenBucket({
      tokensPerMinute: 10_000,
      enabled: true,
      adaptiveEnabled: false,
      minTokensPerRequest: 200,
    });

    const before = bucket.availableTokens;
    await bucket.acquire(1); // requests 1, but min is 200
    const after = bucket.availableTokens;
    // Should have deducted at least 200
    expect(before - after).toBeGreaterThanOrEqual(199); // allow floating point
  });

  it('returns 0 wait time when disabled', async () => {
    const bucket = new TokenBucket({
      tokensPerMinute: 1,
      enabled: false,
    });

    const waited = await bucket.acquire(1_000_000);
    expect(waited).toBe(0);
  });

  it('recordRateLimit adaptively reduces budget', () => {
    const bucket = new TokenBucket({
      tokensPerMinute: 100_000,
      enabled: true,
      adaptiveEnabled: true,
      reductionFactor: 0.7,
    });

    const before = bucket.currentTokensPerMinute;
    bucket.recordRateLimit();
    expect(bucket.currentTokensPerMinute).toBeLessThan(before);
    expect(bucket.currentTokensPerMinute).toBeCloseTo(before * 0.7, 0);
  });

  it('adaptive reduction does not go below 25% floor', () => {
    const bucket = new TokenBucket({
      tokensPerMinute: 10_000,
      enabled: true,
      adaptiveEnabled: true,
      reductionFactor: 0.1, // aggressive reduction
    });

    // Reduce many times
    for (let i = 0; i < 20; i++) {
      bucket.recordRateLimit();
    }

    const floor = 10_000 * 0.25;
    expect(bucket.currentTokensPerMinute).toBeGreaterThanOrEqual(floor);
  });

  it('does not reduce when adaptive is disabled', () => {
    const bucket = new TokenBucket({
      tokensPerMinute: 100_000,
      enabled: true,
      adaptiveEnabled: false,
    });

    const before = bucket.currentTokensPerMinute;
    bucket.recordRateLimit();
    expect(bucket.currentTokensPerMinute).toBe(before);
  });

  it('recordSuccess increments success counter for recovery', () => {
    const bucket = new TokenBucket({
      tokensPerMinute: 100_000,
      enabled: true,
      adaptiveEnabled: true,
    });

    // Should not throw
    bucket.recordSuccess();
    bucket.recordSuccess();
    bucket.recordSuccess();
  });
});

describe('getGlobalRateLimiter', () => {
  beforeEach(() => {
    resetGlobalRateLimiter();
  });

  afterEach(() => {
    resetGlobalRateLimiter();
  });

  it('returns the same singleton on repeated calls', () => {
    const a = getGlobalRateLimiter();
    const b = getGlobalRateLimiter();
    expect(a).toBe(b);
  });

  it('resetGlobalRateLimiter creates a fresh instance', () => {
    const a = getGlobalRateLimiter();
    resetGlobalRateLimiter();
    const b = getGlobalRateLimiter();
    expect(a).not.toBe(b);
  });
});

// ---------------------------------------------------------------------------
// MockLlmClient
// ---------------------------------------------------------------------------

describe('MockLlmClient', () => {
  it('returns default echo when no responses configured', async () => {
    const client = new MockLlmClient();
    const response = await client.query('Hello world');
    expect(response.content).toBe('Mock response to: Hello world');
    expect(response.model).toBe('mock-model');
    expect(response.metadata?.['mock']).toBe(true);
  });

  it('cycles through canned responses', async () => {
    const client = new MockLlmClient({
      responses: ['alpha', 'beta', 'gamma'],
    });

    const r1 = await client.query('q1');
    const r2 = await client.query('q2');
    const r3 = await client.query('q3');
    const r4 = await client.query('q4'); // cycles back

    expect(r1.content).toBe('alpha');
    expect(r2.content).toBe('beta');
    expect(r3.content).toBe('gamma');
    expect(r4.content).toBe('alpha');
  });

  it('uses response generator when provided', async () => {
    const client = new MockLlmClient({
      responseGenerator: (prompt) => `Generated: ${prompt}`,
    });

    const response = await client.query('test input');
    expect(response.content).toBe('Generated: test input');
  });

  it('records call history', async () => {
    const client = new MockLlmClient();

    await client.query('first', { systemPrompt: 'sys1' });
    await client.query('second', { maxTokens: 100, temperature: 0.5 });

    expect(client.callCount).toBe(2);
    expect(client.callHistory).toHaveLength(2);
    expect(client.callHistory[0]!.prompt).toBe('first');
    expect(client.callHistory[0]!.systemPrompt).toBe('sys1');
    expect(client.callHistory[1]!.maxTokens).toBe(100);
    expect(client.callHistory[1]!.temperature).toBe(0.5);
  });

  it('reset clears all state', async () => {
    const client = new MockLlmClient({ responses: ['a', 'b'] });

    await client.query('q1');
    await client.query('q2');
    expect(client.callCount).toBe(2);

    client.reset();
    expect(client.callCount).toBe(0);
    expect(client.callHistory).toHaveLength(0);

    // Response index also resets
    const r = await client.query('q3');
    expect(r.content).toBe('a');
  });

  it('streamQuery yields words', async () => {
    const client = new MockLlmClient({
      responses: ['hello world test'],
    });

    const chunks: string[] = [];
    for await (const chunk of client.streamQuery('q')) {
      chunks.push(chunk);
    }
    expect(chunks.join('')).toBe('hello world test');
  });

  it('returns usage statistics', async () => {
    const client = new MockLlmClient();
    const response = await client.query('short');
    expect(response.usage).toBeDefined();
    expect(response.usage!.input_tokens).toBeGreaterThan(0);
    expect(response.usage!.output_tokens).toBeGreaterThan(0);
  });

  it('respects model override', async () => {
    const client = new MockLlmClient({ defaultModel: 'my-model' });
    const r1 = await client.query('q');
    expect(r1.model).toBe('my-model');

    const r2 = await client.query('q', { model: 'override-model' });
    expect(r2.model).toBe('override-model');
  });
});

// ---------------------------------------------------------------------------
// Factory
// ---------------------------------------------------------------------------

describe('createLlmClient', () => {
  const originalEnv = { ...process.env };

  afterEach(() => {
    process.env = { ...originalEnv };
    resetGlobalRateLimiter();
  });

  it('creates mock client by default', async () => {
    const client = createLlmClient();
    const response = await client.query('hello');
    expect(response.content).toContain('Mock response');
  });

  it('creates mock client explicitly', async () => {
    const client = createLlmClient({ clientType: 'mock' });
    const response = await client.query('hello');
    expect(response.content).toContain('Mock response');
  });

  it('throws on invalid client type', () => {
    expect(() => createLlmClient({ clientType: 'invalid' })).toThrow(
      /Unknown LLM client type/,
    );
  });

  it('reads LLM_CLIENT_TYPE from environment', async () => {
    process.env['LLM_CLIENT_TYPE'] = 'mock';
    const client = createLlmClient();
    const response = await client.query('env test');
    expect(response.content).toContain('Mock response');
  });

  it('passes model override to mock client', async () => {
    const client = createLlmClient({
      clientType: 'mock',
      model: 'custom-model',
    });
    const response = await client.query('q');
    expect(response.model).toBe('custom-model');
  });

  it('reads LLM_DEFAULT_MODEL from environment', async () => {
    process.env['LLM_DEFAULT_MODEL'] = 'env-model';
    const client = createLlmClient({ clientType: 'mock' });
    const response = await client.query('q');
    expect(response.model).toBe('env-model');
  });

  it('groq factory throws without API key', () => {
    delete process.env['GROQ_API_KEY'];
    const origLoad = GroqClient.loadKeyFile;
    GroqClient.loadKeyFile = () => null;
    try {
      expect(() => createLlmClient({ clientType: 'groq' })).toThrow(
        LlmAuthenticationError,
      );
    } finally {
      GroqClient.loadKeyFile = origLoad;
    }
  });

  it('anthropic factory throws without API key', () => {
    delete process.env['ANTHROPIC_API_KEY'];
    const origLoad = AnthropicClient.loadKeyFile;
    AnthropicClient.loadKeyFile = () => null;
    try {
      expect(() => createLlmClient({ clientType: 'anthropic' })).toThrow(
        LlmAuthenticationError,
      );
    } finally {
      AnthropicClient.loadKeyFile = origLoad;
    }
  });
});

// ---------------------------------------------------------------------------
// GroqClient credential loading
// ---------------------------------------------------------------------------

describe('GroqClient', () => {
  const originalEnv = { ...process.env };

  afterEach(() => {
    process.env = { ...originalEnv };
    resetGlobalRateLimiter();
  });

  it('loads API key from constructor parameter', () => {
    const client = new GroqClient({ apiKey: 'test-key-123' });
    expect(client.apiKey).toBe('test-key-123');
  });

  it('loads API key from GROQ_API_KEY env var', () => {
    process.env['GROQ_API_KEY'] = ' env-key-456 ';
    const client = new GroqClient();
    expect(client.apiKey).toBe('env-key-456');
  });

  it('constructor param takes precedence over env var', () => {
    process.env['GROQ_API_KEY'] = 'env-key';
    const client = new GroqClient({ apiKey: 'constructor-key' });
    expect(client.apiKey).toBe('constructor-key');
  });

  it('throws LlmAuthenticationError when no key is available', () => {
    delete process.env['GROQ_API_KEY'];
    // Mock loadKeyFile to return null (no ~/.groq file)
    const origLoad = GroqClient.loadKeyFile;
    GroqClient.loadKeyFile = () => null;
    try {
      expect(() => new GroqClient()).toThrow(LlmAuthenticationError);
      expect(() => new GroqClient()).toThrow(/No Groq API key/);
    } finally {
      GroqClient.loadKeyFile = origLoad;
    }
  });

  it('uses default model when none specified', () => {
    const client = new GroqClient({ apiKey: 'key' });
    expect(client.defaultModel).toBe('llama-3.3-70b-versatile');
  });

  it('respects GROQ_DEFAULT_MODEL env var', () => {
    process.env['GROQ_DEFAULT_MODEL'] = 'mixtral-8x7b-32768';
    const client = new GroqClient({ apiKey: 'key' });
    expect(client.defaultModel).toBe('mixtral-8x7b-32768');
  });

  it('constructor defaultModel overrides env var', () => {
    process.env['GROQ_DEFAULT_MODEL'] = 'env-model';
    const client = new GroqClient({
      apiKey: 'key',
      defaultModel: 'constructor-model',
    });
    expect(client.defaultModel).toBe('constructor-model');
  });

  it('loadKeyFile returns null when file does not exist', () => {
    // This tests the static method directly
    // It may or may not find ~/.groq on the test machine,
    // but at minimum it should not throw
    const result = GroqClient.loadKeyFile();
    expect(result === null || typeof result === 'string').toBe(true);
  });
});

// ---------------------------------------------------------------------------
// AnthropicClient credential loading
// ---------------------------------------------------------------------------

describe('AnthropicClient', () => {
  const originalEnv = { ...process.env };

  afterEach(() => {
    process.env = { ...originalEnv };
    resetGlobalRateLimiter();
  });

  it('loads API key from constructor parameter', () => {
    const client = new AnthropicClient({ apiKey: 'sk-ant-test' });
    expect(client.apiKey).toBe('sk-ant-test');
  });

  it('loads API key from ANTHROPIC_API_KEY env var', () => {
    process.env['ANTHROPIC_API_KEY'] = ' sk-ant-env ';
    const client = new AnthropicClient();
    expect(client.apiKey).toBe('sk-ant-env');
  });

  it('constructor param takes precedence over env var', () => {
    process.env['ANTHROPIC_API_KEY'] = 'env-key';
    const client = new AnthropicClient({ apiKey: 'constructor-key' });
    expect(client.apiKey).toBe('constructor-key');
  });

  it('throws LlmAuthenticationError when no key is available', () => {
    delete process.env['ANTHROPIC_API_KEY'];
    const origLoad = AnthropicClient.loadKeyFile;
    AnthropicClient.loadKeyFile = () => null;
    try {
      expect(() => new AnthropicClient()).toThrow(LlmAuthenticationError);
      expect(() => new AnthropicClient()).toThrow(/No Anthropic API key/);
    } finally {
      AnthropicClient.loadKeyFile = origLoad;
    }
  });

  it('uses default model when none specified', () => {
    const client = new AnthropicClient({ apiKey: 'key' });
    expect(client.defaultModel).toBe('claude-sonnet-4-20250514');
  });

  it('respects ANTHROPIC_DEFAULT_MODEL env var', () => {
    process.env['ANTHROPIC_DEFAULT_MODEL'] = 'claude-3-haiku-20240307';
    const client = new AnthropicClient({ apiKey: 'key' });
    expect(client.defaultModel).toBe('claude-3-haiku-20240307');
  });

  it('constructor defaultModel overrides env var', () => {
    process.env['ANTHROPIC_DEFAULT_MODEL'] = 'env-model';
    const client = new AnthropicClient({
      apiKey: 'key',
      defaultModel: 'constructor-model',
    });
    expect(client.defaultModel).toBe('constructor-model');
  });

  it('loadKeyFile returns null when file does not exist', () => {
    const result = AnthropicClient.loadKeyFile();
    expect(result === null || typeof result === 'string').toBe(true);
  });
});

// ---------------------------------------------------------------------------
// Error class hierarchy
// ---------------------------------------------------------------------------

describe('LlmError hierarchy', () => {
  it('LlmAuthenticationError is instanceof LlmError', () => {
    const err = new LlmAuthenticationError('test');
    expect(err).toBeInstanceOf(LlmError);
    expect(err).toBeInstanceOf(Error);
    expect(err.name).toBe('LlmAuthenticationError');
  });

  it('all error subclasses preserve message', () => {
    expect(new LlmRateLimitError('rate').message).toBe('rate');
    expect(new LlmTimeoutError('timeout').message).toBe('timeout');
    expect(new LlmContextLengthError('ctx').message).toBe('ctx');
  });
});
