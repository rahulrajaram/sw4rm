import * as grpc from '@grpc/grpc-js';
import { BaseClient, ClientOptions } from '../internal/baseClient.js';

type RegistryServiceClient = grpc.Client & {
  RegisterAgent(req: { agent: AgentDescriptor }, meta: grpc.Metadata, opts: grpc.CallOptions, cb: (err: grpc.ServiceError | null, res: { accepted: boolean; reason?: string }) => void): void;
  Heartbeat(req: { agent_id: string; state: string; health?: Record<string, string> }, meta: grpc.Metadata, opts: grpc.CallOptions, cb: (err: grpc.ServiceError | null, res: { ok: boolean }) => void): void;
  DeregisterAgent(req: { agent_id: string; reason?: string }, meta: grpc.Metadata, opts: grpc.CallOptions, cb: (err: grpc.ServiceError | null, res: { ok: boolean }) => void): void;
};

export interface AgentDescriptor {
  agent_id: string;
  name: string;
  description: string;
  capabilities: string[];
  communication_class: string; // enum as string via dynamic loader
  modalities_supported: string[];
  reasoning_connectors: string[];
  public_key?: Uint8Array;
}

export class RegistryClient extends BaseClient {
  private client: RegistryServiceClient;
  constructor(opts: ClientOptions) {
    super(opts);
    this.client = this.getServiceClient<RegistryServiceClient>('sw4rm.registry.RegistryService');
  }

  async registerAgent(agent: AgentDescriptor): Promise<{ accepted: boolean; reason?: string }> {
    const meta = this.metadata();
    const opts: grpc.CallOptions = { deadline: this.deadlineFromNow() };
    return this.withRetryUnary(() => new Promise((resolve, reject) => {
      this.client.RegisterAgent({ agent }, meta, opts, (err, res) => {
        if (err) return reject(err);
        resolve({ accepted: !!res?.accepted, reason: res?.reason });
      });
    }));
  }

  async heartbeat(agentId: string, state: string, health?: Record<string, string>): Promise<boolean> {
    const meta = this.metadata();
    const opts: grpc.CallOptions = { deadline: this.deadlineFromNow() };
    return this.withRetryUnary(() => new Promise<boolean>((resolve, reject) => {
      this.client.Heartbeat({ agent_id: agentId, state, health }, meta, opts, (err, res) => {
        if (err) return reject(err);
        resolve(!!res?.ok);
      });
    }));
  }

  async deregisterAgent(agentId: string, reason?: string): Promise<boolean> {
    const meta = this.metadata();
    const opts: grpc.CallOptions = { deadline: this.deadlineFromNow() };
    return this.withRetryUnary(() => new Promise<boolean>((resolve, reject) => {
      this.client.DeregisterAgent({ agent_id: agentId, reason }, meta, opts, (err, res) => {
        if (err) return reject(err);
        resolve(!!res?.ok);
      });
    }));
  }
}

