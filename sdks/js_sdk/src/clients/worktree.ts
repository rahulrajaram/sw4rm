import * as grpc from '@grpc/grpc-js';
import { BaseClient, ClientOptions } from '../internal/baseClient.js';
import { DefaultWorktreePolicy, WorktreePolicyHook } from '../internal/worktreePolicy.js';

type WorktreeServiceClient = grpc.Client & {
  Bind(req: { agent_id: string; repo_id: string; worktree_id: string }, meta: grpc.Metadata, opts: grpc.CallOptions, cb: (err: grpc.ServiceError | null, res: { ok: boolean; reason?: string }) => void): void;
  Unbind(req: { agent_id: string }, meta: grpc.Metadata, opts: grpc.CallOptions, cb: (err: grpc.ServiceError | null, res: { ok: boolean }) => void): void;
  RequestSwitch(req: { agent_id: string; target_worktree_id: string; requires_hitl: boolean }, meta: grpc.Metadata, opts: grpc.CallOptions, cb: (err: grpc.ServiceError | null, res: { repo_id?: string; worktree_id?: string; state: string }) => void): void;
  ApproveSwitch(req: { agent_id: string; target_worktree_id: string; ttl_ms: string | number }, meta: grpc.Metadata, opts: grpc.CallOptions, cb: (err: grpc.ServiceError | null, res: { state: string }) => void): void;
  RejectSwitch(req: { agent_id: string; reason?: string }, meta: grpc.Metadata, opts: grpc.CallOptions, cb: (err: grpc.ServiceError | null, res: { state: string }) => void): void;
  Status(req: { agent_id: string }, meta: grpc.Metadata, opts: grpc.CallOptions, cb: (err: grpc.ServiceError | null, res: { repo_id?: string; worktree_id?: string; state: string }) => void): void;
};

export class WorktreeClient extends BaseClient {
  private client: WorktreeServiceClient;
  private policy: WorktreePolicyHook;
  constructor(opts: ClientOptions) {
    super(opts);
    this.client = this.getServiceClient<WorktreeServiceClient>('sw4rm.worktree.WorktreeService');
    this.policy = new DefaultWorktreePolicy();
  }

  setPolicy(policy: WorktreePolicyHook) { this.policy = policy; }

  async bind(agentId: string, repoId: string, worktreeId: string): Promise<{ ok: boolean; reason?: string }> {
    const meta = this.metadata();
    const opts: grpc.CallOptions = { deadline: this.deadlineFromNow() };
    if (!this.policy.canBind({ agent_id: agentId, current_state: 'UNKNOWN' }, repoId, worktreeId)) {
      throw new Error('WorktreePolicy denied bind');
    }
    return this.withRetryUnary(() => new Promise((resolve, reject) => {
      this.client.Bind({ agent_id: agentId, repo_id: repoId, worktree_id: worktreeId }, meta, opts, (err, res) => {
        if (err) return reject(err);
        resolve({ ok: !!res?.ok, reason: res?.reason });
      });
    }));
  }

  async unbind(agentId: string): Promise<boolean> {
    const meta = this.metadata();
    const opts: grpc.CallOptions = { deadline: this.deadlineFromNow() };
    if (!this.policy.canUnbind({ agent_id: agentId, current_state: 'UNKNOWN' })) {
      throw new Error('WorktreePolicy denied unbind');
    }
    return this.withRetryUnary(() => new Promise<boolean>((resolve, reject) => {
      this.client.Unbind({ agent_id: agentId }, meta, opts, (err, res) => {
        if (err) return reject(err);
        resolve(!!res?.ok);
      });
    }));
  }

  async requestSwitch(agentId: string, targetWorktreeId: string, requiresHitl: boolean): Promise<{ state: string; repo_id?: string; worktree_id?: string }> {
    const meta = this.metadata();
    const opts: grpc.CallOptions = { deadline: this.deadlineFromNow() };
    if (!this.policy.canSwitch({ agent_id: agentId, current_state: 'UNKNOWN', target_worktree_id: targetWorktreeId })) {
      throw new Error('WorktreePolicy denied switch');
    }
    return this.withRetryUnary(() => new Promise((resolve, reject) => {
      this.client.RequestSwitch({ agent_id: agentId, target_worktree_id: targetWorktreeId, requires_hitl: requiresHitl }, meta, opts, (err, res) => {
        if (err) return reject(err);
        resolve(res);
      });
    }));
  }

  async approveSwitch(agentId: string, targetWorktreeId: string, ttlMs: number): Promise<string> {
    const meta = this.metadata();
    const opts: grpc.CallOptions = { deadline: this.deadlineFromNow() };
    return this.withRetryUnary(() => new Promise<string>((resolve, reject) => {
      this.client.ApproveSwitch({ agent_id: agentId, target_worktree_id: targetWorktreeId, ttl_ms: ttlMs }, meta, opts, (err, res) => {
        if (err) return reject(err);
        resolve(res?.state ?? 'UNBOUND');
      });
    }));
  }

  async rejectSwitch(agentId: string, reason?: string): Promise<string> {
    const meta = this.metadata();
    const opts: grpc.CallOptions = { deadline: this.deadlineFromNow() };
    return this.withRetryUnary(() => new Promise<string>((resolve, reject) => {
      this.client.RejectSwitch({ agent_id: agentId, reason }, meta, opts, (err, res) => {
        if (err) return reject(err);
        resolve(res?.state ?? 'UNBOUND');
      });
    }));
  }

  async status(agentId: string): Promise<{ state: string; repo_id?: string; worktree_id?: string }> {
    const meta = this.metadata();
    const opts: grpc.CallOptions = { deadline: this.deadlineFromNow() };
    return this.withRetryUnary(() => new Promise((resolve, reject) => {
      this.client.Status({ agent_id: agentId }, meta, opts, (err, res) => {
        if (err) return reject(err);
        resolve(res);
      });
    }));
  }
}
