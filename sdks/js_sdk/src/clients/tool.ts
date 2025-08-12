import * as grpc from '@grpc/grpc-js';
import { BaseClient, ClientOptions } from '../internal/baseClient.js';
import { Sw4rmError } from '../internal/errorMapping.js';

type ToolServiceClient = grpc.Client & {
  Call(req: ToolCall, meta: grpc.Metadata, opts: grpc.CallOptions, cb: (err: grpc.ServiceError | null, res: ToolFrame) => void): void;
  CallStream(req: ToolCall, meta?: grpc.Metadata): grpc.ClientReadableStream<ToolFrame>;
  Cancel(req: ToolCall, meta: grpc.Metadata, opts: grpc.CallOptions, cb: (err: grpc.ServiceError | null, res: ToolError) => void): void;
};

export interface ExecutionPolicy {
  timeout?: { seconds: number | string; nanos?: number };
  max_retries?: number;
  backoff?: string;
  worktree_required?: boolean;
  network_policy?: string;
  privilege_level?: string;
  budget_cpu_ms?: string | number;
  budget_wall_ms?: string | number;
}

export interface ToolCall {
  call_id: string;
  tool_name: string;
  provider_id?: string;
  content_type: string;
  args: Uint8Array;
  policy?: ExecutionPolicy;
  stream?: boolean;
}

export interface ToolFrame {
  call_id: string;
  frame_no: string | number;
  final: boolean;
  content_type: string;
  data: Uint8Array;
  summary?: Uint8Array;
}

export interface ToolError { call_id: string; error_code?: string; message?: string }

export class ToolClient extends BaseClient {
  private client: ToolServiceClient;
  private getWorktreeState?: () => { state: string };

  constructor(opts: ClientOptions, deps?: { getWorktreeState?: () => { state: string } }) {
    super(opts);
    this.client = this.getServiceClient<ToolServiceClient>('sw4rm.tool.ToolService');
    this.getWorktreeState = deps?.getWorktreeState;
  }

  private ensureWorktreeIfNeeded(call: ToolCall) {
    const need = call.policy?.worktree_required;
    if (!need) return;
    const st = this.getWorktreeState?.();
    if (!st || st.state === 'UNBOUND' || st.state === 'BIND_FAILED') {
      throw new Sw4rmError('worktree_not_bound', 6); // VALIDATION_ERROR
    }
  }

  async call(call: ToolCall): Promise<ToolFrame> {
    this.ensureWorktreeIfNeeded(call);
    const meta = this.metadata();
    const opts: grpc.CallOptions = { deadline: this.deadlineFromNow() };
    return this.withRetryUnary(() => new Promise<ToolFrame>((resolve, reject) => {
      this.client.Call(call, meta, opts, (err, res) => {
        if (err) return reject(err);
        resolve(res);
      });
    }));
  }

  callStream(call: ToolCall, meta?: grpc.Metadata): grpc.ClientReadableStream<ToolFrame> {
    this.ensureWorktreeIfNeeded(call);
    const m = this.metadata(meta);
    return this.client.CallStream(call, m);
  }

  async cancel(call: ToolCall): Promise<ToolError> {
    const meta = this.metadata();
    const opts: grpc.CallOptions = { deadline: this.deadlineFromNow() };
    return this.withRetryUnary(() => new Promise<ToolError>((resolve, reject) => {
      this.client.Cancel(call, meta, opts, (err, res) => {
        if (err) return reject(err);
        resolve(res);
      });
    }));
  }
}

