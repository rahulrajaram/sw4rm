// Simple interceptor interfaces for unary calls

export interface UnaryContext {
  method: string;
  metadata: Map<string, string>;
  startTime: number;
}

export interface UnaryInterceptor {
  onRequest?(ctx: UnaryContext): void;
  onResponse?(ctx: UnaryContext, status: { ok: boolean; error?: unknown; durationMs: number }): void;
}

export class InterceptorChain {
  private chain: UnaryInterceptor[] = [];
  use(i: UnaryInterceptor) { this.chain.push(i); }
  runRequest(ctx: UnaryContext) { for (const i of this.chain) i.onRequest?.(ctx); }
  runResponse(ctx: UnaryContext, status: { ok: boolean; error?: unknown; durationMs: number }) { for (const i of this.chain) i.onResponse?.(ctx, status); }
}

export function timingInterceptor(): UnaryInterceptor {
  return {
    onRequest(ctx) {
      // no-op; start time already in ctx
    },
    onResponse(ctx, status) {
      // Could emit to metrics sink; default to console.debug for now
      if (typeof console !== 'undefined' && (console as any).debug) {
        (console as any).debug(`[rpc] ${ctx.method} duration=${status.durationMs}ms ok=${status.ok}`);
      }
    },
  };
}

export function loggingInterceptor(): UnaryInterceptor {
  return {
    onResponse(ctx, status) {
      if (!status.ok && console && console.warn) {
        console.warn(`[rpc] ${ctx.method} failed`, status.error);
      }
    },
  };
}

