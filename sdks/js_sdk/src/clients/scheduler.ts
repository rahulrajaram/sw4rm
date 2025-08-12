import * as grpc from '@grpc/grpc-js';
import { BaseClient, ClientOptions } from '../internal/baseClient.js';
import { msToDuration } from '../internal/time.js';

type SchedulerServiceClient = grpc.Client & {
  SubmitTask(req: SubmitTaskRequest, meta: grpc.Metadata, opts: grpc.CallOptions, cb: (err: grpc.ServiceError | null, res: SubmitTaskResponse) => void): void;
  RequestPreemption(req: PreemptRequest, meta: grpc.Metadata, opts: grpc.CallOptions, cb: (err: grpc.ServiceError | null, res: PreemptResponse) => void): void;
  ShutdownAgent(req: ShutdownAgentRequest, meta: grpc.Metadata, opts: grpc.CallOptions, cb: (err: grpc.ServiceError | null, res: ShutdownAgentResponse) => void): void;
  PollActivityBuffer(req: PollActivityBufferRequest, meta: grpc.Metadata, opts: grpc.CallOptions, cb: (err: grpc.ServiceError | null, res: PollActivityBufferResponse) => void): void;
  PurgeActivity(req: PurgeActivityRequest, meta: grpc.Metadata, opts: grpc.CallOptions, cb: (err: grpc.ServiceError | null, res: PurgeActivityResponse) => void): void;
};

// Types aligned with protos/scheduler.proto (dynamic loader shapes)
export interface SubmitTaskRequest {
  agent_id: string;
  task_id: string;
  priority: number; // -19..20
  params: Uint8Array;
  content_type: string;
  scope: string;
}
export interface SubmitTaskResponse { accepted: boolean; reason?: string }

export interface PreemptRequest { agent_id: string; task_id: string; reason?: string }
export interface PreemptResponse { enqueued: boolean }

export interface ShutdownAgentRequest { agent_id: string; grace_period?: { seconds: number | string; nanos?: number } }
export interface ShutdownAgentResponse { ok: boolean }

export interface PollActivityBufferRequest { agent_id: string }
export interface ActivityEntry { task_id: string; repo_id: string; worktree_id: string; branch: string; description: string; timestamp: string }
export interface PollActivityBufferResponse { entries: ActivityEntry[] }

export interface PurgeActivityRequest { agent_id: string; task_ids: string[] }
export interface PurgeActivityResponse { purged: number }

export class SchedulerClient extends BaseClient {
  private client: SchedulerServiceClient;

  constructor(opts: ClientOptions) {
    super(opts);
    this.client = this.getServiceClient<SchedulerServiceClient>('sw4rm.scheduler.SchedulerService');
  }

  async submitTask(req: SubmitTaskRequest): Promise<SubmitTaskResponse> {
    validatePriority(req.priority);
    const meta = this.metadata();
    const opts: grpc.CallOptions = { deadline: this.deadlineFromNow() };
    return this.withRetryUnary(() => new Promise<SubmitTaskResponse>((resolve, reject) => {
      this.client.SubmitTask(req, meta, opts, (err, res) => {
        if (err) return reject(err);
        resolve({ accepted: !!res?.accepted, reason: res?.reason });
      });
    }), 'sw4rm.scheduler.SubmitTask', meta);
  }

  async requestPreemption(agentId: string, taskId: string, reason?: string): Promise<PreemptResponse> {
    const meta = this.metadata();
    const opts: grpc.CallOptions = { deadline: this.deadlineFromNow() };
    const req: PreemptRequest = { agent_id: agentId, task_id: taskId, reason };
    return this.withRetryUnary(() => new Promise<PreemptResponse>((resolve, reject) => {
      this.client.RequestPreemption(req, meta, opts, (err, res) => {
        if (err) return reject(err);
        resolve({ enqueued: !!res?.enqueued });
      });
    }), 'sw4rm.scheduler.RequestPreemption', meta);
  }

  async shutdownAgent(agentId: string, graceMs: number): Promise<ShutdownAgentResponse> {
    const meta = this.metadata();
    const opts: grpc.CallOptions = { deadline: this.deadlineFromNow() };
    const req: ShutdownAgentRequest = { agent_id: agentId, grace_period: msToDuration(graceMs) };
    return this.withRetryUnary(() => new Promise<ShutdownAgentResponse>((resolve, reject) => {
      this.client.ShutdownAgent(req, meta, opts, (err, res) => {
        if (err) return reject(err);
        resolve({ ok: !!res?.ok });
      });
    }), 'sw4rm.scheduler.ShutdownAgent', meta);
  }

  async pollActivityBuffer(agentId: string): Promise<ActivityEntry[]> {
    const meta = this.metadata();
    const opts: grpc.CallOptions = { deadline: this.deadlineFromNow() };
    const req: PollActivityBufferRequest = { agent_id: agentId };
    return this.withRetryUnary(() => new Promise<ActivityEntry[]>((resolve, reject) => {
      this.client.PollActivityBuffer(req, meta, opts, (err, res) => {
        if (err) return reject(err);
        resolve(res?.entries ?? []);
      });
    }), 'sw4rm.scheduler.PollActivityBuffer', meta);
  }

  async purgeActivity(agentId: string, taskIds: string[]): Promise<number> {
    const meta = this.metadata();
    const opts: grpc.CallOptions = { deadline: this.deadlineFromNow() };
    const req: PurgeActivityRequest = { agent_id: agentId, task_ids: taskIds };
    return this.withRetryUnary(() => new Promise<number>((resolve, reject) => {
      this.client.PurgeActivity(req, meta, opts, (err, res) => {
        if (err) return reject(err);
        resolve(Number(res?.purged ?? 0));
      });
    }), 'sw4rm.scheduler.PurgeActivity', meta);
  }
}

function validatePriority(p: number) {
  if (!Number.isFinite(p) || p < -19 || p > 20) {
    throw new Error('priority must be in range -19..20');
  }
}
