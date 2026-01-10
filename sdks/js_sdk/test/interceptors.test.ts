// Copyright 2025 Rahul Rajaram
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import { describe, it, expect, vi, beforeEach } from 'vitest';
import {
  InterceptorChain,
  timingInterceptor,
  loggingInterceptor,
  type UnaryContext,
  type UnaryInterceptor,
} from '../src/internal/interceptors.js';

/**
 * Tests for gRPC interceptors.
 *
 * These tests verify the interceptor chain, timing interceptor, and
 * logging interceptor functionality.
 *
 * Ported from: sdks/py_sdk/tests/test_interceptors.py
 */

function createContext(method: string = '/test/Method'): UnaryContext {
  return {
    method,
    metadata: new Map<string, string>([
      ['user-agent', 'test-agent'],
      ['x-correlation-id', 'corr-123'],
    ]),
    startTime: Date.now(),
  };
}

describe('Interceptors', () => {
  describe('InterceptorChain', () => {
    it('should initialize empty chain', () => {
      const chain = new InterceptorChain();
      expect(chain).toBeDefined();
    });

    it('should add interceptors to chain', () => {
      const chain = new InterceptorChain();
      const interceptor: UnaryInterceptor = {
        onRequest: vi.fn(),
        onResponse: vi.fn(),
      };

      chain.use(interceptor);

      const ctx = createContext();
      chain.runRequest(ctx);

      expect(interceptor.onRequest).toHaveBeenCalledWith(ctx);
    });

    it('should run multiple interceptors in order', () => {
      const chain = new InterceptorChain();
      const order: string[] = [];

      const interceptor1: UnaryInterceptor = {
        onRequest: () => order.push('1-request'),
        onResponse: () => order.push('1-response'),
      };

      const interceptor2: UnaryInterceptor = {
        onRequest: () => order.push('2-request'),
        onResponse: () => order.push('2-response'),
      };

      chain.use(interceptor1);
      chain.use(interceptor2);

      const ctx = createContext();
      chain.runRequest(ctx);
      chain.runResponse(ctx, { ok: true, durationMs: 100 });

      expect(order).toEqual(['1-request', '2-request', '1-response', '2-response']);
    });

    it('should handle interceptors with only onRequest', () => {
      const chain = new InterceptorChain();
      const onRequest = vi.fn();

      chain.use({ onRequest });

      const ctx = createContext();
      chain.runRequest(ctx);
      chain.runResponse(ctx, { ok: true, durationMs: 100 });

      expect(onRequest).toHaveBeenCalledTimes(1);
    });

    it('should handle interceptors with only onResponse', () => {
      const chain = new InterceptorChain();
      const onResponse = vi.fn();

      chain.use({ onResponse });

      const ctx = createContext();
      chain.runRequest(ctx);
      chain.runResponse(ctx, { ok: true, durationMs: 100 });

      expect(onResponse).toHaveBeenCalledTimes(1);
    });

    it('should pass context to all interceptors', () => {
      const chain = new InterceptorChain();
      const receivedContexts: UnaryContext[] = [];

      chain.use({
        onRequest: (ctx) => receivedContexts.push(ctx),
      });
      chain.use({
        onRequest: (ctx) => receivedContexts.push(ctx),
      });

      const ctx = createContext('/test/MyMethod');
      chain.runRequest(ctx);

      expect(receivedContexts).toHaveLength(2);
      expect(receivedContexts[0].method).toBe('/test/MyMethod');
      expect(receivedContexts[1].method).toBe('/test/MyMethod');
    });

    it('should pass status to response interceptors', () => {
      const chain = new InterceptorChain();
      const receivedStatuses: { ok: boolean; error?: unknown; durationMs: number }[] = [];

      chain.use({
        onResponse: (_, status) => receivedStatuses.push(status),
      });

      const ctx = createContext();

      // Success case
      chain.runResponse(ctx, { ok: true, durationMs: 50 });

      // Error case
      chain.runResponse(ctx, { ok: false, error: new Error('test'), durationMs: 100 });

      expect(receivedStatuses).toHaveLength(2);
      expect(receivedStatuses[0].ok).toBe(true);
      expect(receivedStatuses[0].durationMs).toBe(50);
      expect(receivedStatuses[1].ok).toBe(false);
      expect(receivedStatuses[1].error).toBeInstanceOf(Error);
    });
  });

  describe('timingInterceptor', () => {
    let consoleSpy: ReturnType<typeof vi.spyOn>;

    beforeEach(() => {
      consoleSpy = vi.spyOn(console, 'debug').mockImplementation(() => {});
    });

    it('should be a valid interceptor', () => {
      const interceptor = timingInterceptor();
      expect(interceptor).toHaveProperty('onRequest');
      expect(interceptor).toHaveProperty('onResponse');
    });

    it('should log timing on response', () => {
      const interceptor = timingInterceptor();
      const ctx = createContext('/test/TimedMethod');

      interceptor.onResponse?.(ctx, { ok: true, durationMs: 150 });

      expect(consoleSpy).toHaveBeenCalledWith(
        expect.stringContaining('/test/TimedMethod')
      );
      expect(consoleSpy).toHaveBeenCalledWith(
        expect.stringContaining('duration=150ms')
      );
    });

    it('should include ok status in log', () => {
      const interceptor = timingInterceptor();
      const ctx = createContext();

      interceptor.onResponse?.(ctx, { ok: true, durationMs: 100 });
      expect(consoleSpy).toHaveBeenCalledWith(expect.stringContaining('ok=true'));

      interceptor.onResponse?.(ctx, { ok: false, durationMs: 100 });
      expect(consoleSpy).toHaveBeenCalledWith(expect.stringContaining('ok=false'));
    });
  });

  describe('loggingInterceptor', () => {
    let consoleSpy: ReturnType<typeof vi.spyOn>;

    beforeEach(() => {
      consoleSpy = vi.spyOn(console, 'warn').mockImplementation(() => {});
    });

    it('should be a valid interceptor', () => {
      const interceptor = loggingInterceptor();
      expect(interceptor).toHaveProperty('onResponse');
    });

    it('should log warning on error', () => {
      const interceptor = loggingInterceptor();
      const ctx = createContext('/test/FailedMethod');
      const error = new Error('Something went wrong');

      interceptor.onResponse?.(ctx, { ok: false, error, durationMs: 100 });

      expect(consoleSpy).toHaveBeenCalledWith(
        expect.stringContaining('/test/FailedMethod'),
        error
      );
    });

    it('should not log on success', () => {
      const interceptor = loggingInterceptor();
      const ctx = createContext();

      interceptor.onResponse?.(ctx, { ok: true, durationMs: 100 });

      expect(consoleSpy).not.toHaveBeenCalled();
    });
  });

  describe('custom interceptors', () => {
    it('should support correlation ID injection', () => {
      const correlationInterceptor: UnaryInterceptor = {
        onRequest: (ctx) => {
          ctx.metadata.set('x-correlation-id', 'custom-corr-456');
        },
      };

      const chain = new InterceptorChain();
      chain.use(correlationInterceptor);

      const ctx = createContext();
      chain.runRequest(ctx);

      expect(ctx.metadata.get('x-correlation-id')).toBe('custom-corr-456');
    });

    it('should support metrics collection', () => {
      const metrics: { method: string; durationMs: number; success: boolean }[] = [];

      const metricsInterceptor: UnaryInterceptor = {
        onResponse: (ctx, status) => {
          metrics.push({
            method: ctx.method,
            durationMs: status.durationMs,
            success: status.ok,
          });
        },
      };

      const chain = new InterceptorChain();
      chain.use(metricsInterceptor);

      chain.runResponse(createContext('/service/Method1'), { ok: true, durationMs: 50 });
      chain.runResponse(createContext('/service/Method2'), { ok: false, durationMs: 100 });

      expect(metrics).toHaveLength(2);
      expect(metrics[0]).toEqual({ method: '/service/Method1', durationMs: 50, success: true });
      expect(metrics[1]).toEqual({ method: '/service/Method2', durationMs: 100, success: false });
    });

    it('should support authentication injection', () => {
      const authInterceptor: UnaryInterceptor = {
        onRequest: (ctx) => {
          ctx.metadata.set('authorization', 'Bearer token-123');
        },
      };

      const chain = new InterceptorChain();
      chain.use(authInterceptor);

      const ctx = createContext();
      chain.runRequest(ctx);

      expect(ctx.metadata.get('authorization')).toBe('Bearer token-123');
    });

    it('should support request/response logging', () => {
      const logs: string[] = [];

      const logInterceptor: UnaryInterceptor = {
        onRequest: (ctx) => {
          logs.push(`REQUEST: ${ctx.method}`);
        },
        onResponse: (ctx, status) => {
          logs.push(`RESPONSE: ${ctx.method} [${status.ok ? 'OK' : 'ERROR'}]`);
        },
      };

      const chain = new InterceptorChain();
      chain.use(logInterceptor);

      const ctx = createContext('/api/Test');
      chain.runRequest(ctx);
      chain.runResponse(ctx, { ok: true, durationMs: 100 });

      expect(logs).toEqual([
        'REQUEST: /api/Test',
        'RESPONSE: /api/Test [OK]',
      ]);
    });
  });

  describe('integration', () => {
    it('should work with full interceptor chain', () => {
      const events: string[] = [];

      const chain = new InterceptorChain();

      // Add timing
      chain.use(timingInterceptor());

      // Add logging
      chain.use(loggingInterceptor());

      // Add custom tracking
      chain.use({
        onRequest: () => events.push('request'),
        onResponse: () => events.push('response'),
      });

      const ctx = createContext('/full/Integration');

      // Simulate request/response cycle
      chain.runRequest(ctx);
      chain.runResponse(ctx, { ok: true, durationMs: 200 });

      expect(events).toContain('request');
      expect(events).toContain('response');
    });

    it('should handle multiple requests in sequence', () => {
      const durations: number[] = [];

      const chain = new InterceptorChain();
      chain.use({
        onResponse: (_, status) => durations.push(status.durationMs),
      });

      for (let i = 0; i < 5; i++) {
        const ctx = createContext(`/method/${i}`);
        chain.runRequest(ctx);
        chain.runResponse(ctx, { ok: true, durationMs: (i + 1) * 10 });
      }

      expect(durations).toEqual([10, 20, 30, 40, 50]);
    });

    it('should handle concurrent contexts independently', () => {
      const chain = new InterceptorChain();
      const receivedMethods: string[] = [];

      chain.use({
        onResponse: (ctx) => receivedMethods.push(ctx.method),
      });

      const ctx1 = createContext('/method/1');
      const ctx2 = createContext('/method/2');
      const ctx3 = createContext('/method/3');

      // Start all requests
      chain.runRequest(ctx1);
      chain.runRequest(ctx2);
      chain.runRequest(ctx3);

      // Complete in different order
      chain.runResponse(ctx2, { ok: true, durationMs: 50 });
      chain.runResponse(ctx1, { ok: true, durationMs: 100 });
      chain.runResponse(ctx3, { ok: true, durationMs: 75 });

      expect(receivedMethods).toEqual(['/method/2', '/method/1', '/method/3']);
    });
  });
});
