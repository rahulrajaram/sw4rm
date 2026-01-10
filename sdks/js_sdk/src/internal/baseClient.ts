// Base gRPC client with metadata, deadlines, and simple retry
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import * as grpc from '@grpc/grpc-js';
import * as protoLoader from '@grpc/proto-loader';
import { mapGrpcStatusToErrorCode, Sw4rmError } from './errorMapping.js';
import { ErrorCodeMapper, GrpcErrorInfo } from './errorMapper.js';
import { InterceptorChain, UnaryContext, timingInterceptor, loggingInterceptor } from './interceptors.js';
import { uuidv4 } from './ids.js';

export interface RetryPolicy {
  maxAttempts: number; // includes initial
  initialBackoffMs: number;
  maxBackoffMs: number;
  multiplier: number; // exponential factor
}

export interface ClientOptions {
  address: string; // host:port
  deadlineMs?: number; // per-call deadline
  retry?: RetryPolicy;
  userAgent?: string;
  interceptors?: (chain: InterceptorChain) => void;
  errorMapper?: (m: ErrorCodeMapper) => void;
}

export class BaseClient {
  protected readonly address: string;
  protected readonly deadlineMs: number;
  protected readonly retry: RetryPolicy;
  protected readonly userAgent: string;
  private readonly pkgDef: protoLoader.PackageDefinition;
  private readonly root: any;
  protected readonly interceptors = new InterceptorChain();
  protected readonly errorMapper = new ErrorCodeMapper();

  constructor(opts: ClientOptions) {
    this.address = opts.address;
    this.deadlineMs = opts.deadlineMs ?? 30000;
    this.retry = opts.retry ?? { maxAttempts: 1, initialBackoffMs: 200, maxBackoffMs: 2000, multiplier: 2 };
    this.userAgent = opts.userAgent ?? 'sw4rm-js-sdk/0.1';

    const __filename = fileURLToPath(import.meta.url);
    const __dirname = path.dirname(__filename);

    // Resolve protos directory - try multiple locations for dev vs npm package
    const protosDir = this.resolveProtosDir(__dirname);

    const loaderOpts: protoLoader.Options = {
      keepCase: true,
      longs: String,
      enums: String,
      defaults: true,
      oneofs: true,
      includeDirs: [protosDir],
    };
    this.pkgDef = protoLoader.loadSync([
      'common.proto',
      'registry.proto',
      'router.proto',
      'scheduler.proto',
      'scheduler_policy.proto',
      'hitl.proto',
      'worktree.proto',
      'tool.proto',
      'connector.proto',
      'negotiation.proto',
      'reasoning.proto',
      'logging.proto',
      'policy.proto',
      'activity.proto',
    ], loaderOpts);
    this.root = grpc.loadPackageDefinition(this.pkgDef);
    // Default interceptors: timing + error logging; caller can add more
    this.interceptors.use(timingInterceptor());
    this.interceptors.use(loggingInterceptor());
    if (opts.interceptors) opts.interceptors(this.interceptors);
    if (opts.errorMapper) opts.errorMapper(this.errorMapper);
  }

  /**
   * Resolves the protos directory, checking multiple locations:
   * 1. npm package: ./protos relative to package root
   * 2. Monorepo dev: ../../../../protos relative to this file
   */
  private resolveProtosDir(dirname: string): string {
    // Candidate paths in order of preference
    const candidates = [
      // npm package structure: node_modules/@sw4rm/js-sdk/protos
      path.resolve(dirname, '../../protos'),
      // Alternative npm structure: dist/esm/internal -> protos
      path.resolve(dirname, '../../../protos'),
      // Monorepo development: sdks/js_sdk/src/internal -> protos
      path.resolve(dirname, '../../../../protos'),
    ];

    for (const candidate of candidates) {
      if (fs.existsSync(candidate) && fs.existsSync(path.join(candidate, 'common.proto'))) {
        return candidate;
      }
    }

    // Fallback to monorepo path (will error at load time if not found)
    return candidates[candidates.length - 1];
  }

  protected channelCredentials(): grpc.ChannelCredentials {
    return grpc.credentials.createInsecure(); // hook for mTLS later
  }

  protected metadata(base?: grpc.Metadata): grpc.Metadata {
    const md = base ? base.clone() : new grpc.Metadata();
    // Correlation will often also be carried in envelopes; still useful at transport level
    if (!md.get('user-agent').length) md.set('user-agent', this.userAgent);
    if (!md.get('x-correlation-id').length) md.set('x-correlation-id', uuidv4());
    return md;
  }

  protected deadlineFromNow(): Date {
    return new Date(Date.now() + this.deadlineMs);
  }

  // Resolve a service client by its fully-qualified name (e.g., 'sw4rm.router.RouterService')
  protected getServiceClient<T = any>(fqn: string): T {
    const parts = fqn.split('.');
    let ns: any = this.root;
    for (const p of parts) {
      ns = ns?.[p];
      if (!ns) throw new Error(`Service not found: ${fqn}`);
    }
    const ServiceCtor = ns as unknown as grpc.ServiceClientConstructor;
    return new ServiceCtor(this.address, this.channelCredentials()) as unknown as T;
  }

  protected async withRetryUnary<Res>(fn: () => Promise<Res>, methodName = 'unknown', mdForCtx?: grpc.Metadata): Promise<Res> {
    let attempt = 0;
    let backoff = this.retry.initialBackoffMs;
    for (;;) {
      try {
        const mdMap = new Map<string, string>();
        if (mdForCtx?.getMap) {
          const rawMap = mdForCtx.getMap();
          for (const [k, v] of Object.entries(rawMap)) {
            mdMap.set(k, typeof v === 'string' ? v : String(v));
          }
        }
        const ctx: UnaryContext = { method: methodName, metadata: mdMap, startTime: Date.now() };
        this.interceptors.runRequest(ctx);
        const res = await fn();
        this.interceptors.runResponse(ctx, { ok: true, durationMs: Date.now() - ctx.startTime });
        return res;
      } catch (e: any) {
        attempt++;
        const status = typeof e?.code === 'number' ? e.code : undefined;
        if (attempt >= this.retry.maxAttempts) {
          const info: GrpcErrorInfo = { status, message: e?.message, details: e?.details };
          const mapped = this.errorMapper.map(info, (s?: number) => mapGrpcStatusToErrorCode(s ?? -1));
          const err = new Sw4rmError(
            e?.details || e?.message || 'gRPC call failed',
            mapped,
            { grpcStatus: status, details: e?.details || e?.message }
          );
          const mdMap = new Map<string, string>();
        if (mdForCtx?.getMap) {
          const rawMap = mdForCtx.getMap();
          for (const [k, v] of Object.entries(rawMap)) {
            mdMap.set(k, typeof v === 'string' ? v : String(v));
          }
        }
        const ctx: UnaryContext = { method: methodName, metadata: mdMap, startTime: Date.now() };
          this.interceptors.runResponse(ctx, { ok: false, error: err, durationMs: 0 });
          throw err;
        }
        await new Promise(r => setTimeout(r, backoff));
        backoff = Math.min(this.retry.maxBackoffMs, Math.floor(backoff * this.retry.multiplier));
      }
    }
  }
}
