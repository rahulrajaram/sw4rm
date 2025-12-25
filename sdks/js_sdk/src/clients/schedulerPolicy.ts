import * as grpc from '@grpc/grpc-js';
import { BaseClient, ClientOptions } from '../internal/baseClient.js';

type SchedulerPolicyServiceClient = grpc.Client & {
  SetWagglePolicy(req: { policy?: unknown }, meta: grpc.Metadata, opts: grpc.CallOptions, cb: (err: grpc.ServiceError | null, res: { ok: boolean; reason?: string }) => void): void;
  GetWagglePolicy(req: Record<string, never>, meta: grpc.Metadata, opts: grpc.CallOptions, cb: (err: grpc.ServiceError | null, res: { policy?: unknown }) => void): void;
  SetPolicyProfiles(req: { profiles: unknown[] }, meta: grpc.Metadata, opts: grpc.CallOptions, cb: (err: grpc.ServiceError | null, res: { ok: boolean; reason?: string }) => void): void;
  ListPolicyProfiles(req: Record<string, never>, meta: grpc.Metadata, opts: grpc.CallOptions, cb: (err: grpc.ServiceError | null, res: { profiles: unknown[] }) => void): void;
  GetEffectivePolicy(req: { negotiation_id: string }, meta: grpc.Metadata, opts: grpc.CallOptions, cb: (err: grpc.ServiceError | null, res: { effective?: any }) => void): void;
  SubmitEvaluation(req: { negotiation_id: string; report?: any }, meta: grpc.Metadata, opts: grpc.CallOptions, cb: (err: grpc.ServiceError | null, res: { accepted: boolean; reason?: string }) => void): void;
  HitlAction(req: { negotiation_id: string; action: string; rationale?: string }, meta: grpc.Metadata, opts: grpc.CallOptions, cb: (err: grpc.ServiceError | null, res: { ok: boolean; reason?: string }) => void): void;
};

export class SchedulerPolicyClient extends BaseClient {
  private client: SchedulerPolicyServiceClient;
  constructor(opts: ClientOptions) {
    super(opts);
    this.client = this.getServiceClient<SchedulerPolicyServiceClient>('sw4rm.scheduler.SchedulerPolicyService');
  }

  private unary<T>(method: keyof SchedulerPolicyServiceClient, req: any): Promise<T> {
    const meta = this.metadata();
    const opts: grpc.CallOptions = { deadline: this.deadlineFromNow() };
    return this.withRetryUnary(() => new Promise<T>((resolve, reject) => {
      // @ts-expect-error dynamic
      this.client[method](req, meta, opts, (err: grpc.ServiceError | null, res: T) => {
        if (err) return reject(err);
        resolve(res);
      });
    }));
  }

  setWagglePolicy(policy: any) { return this.unary<{ ok: boolean; reason?: string }>('SetWagglePolicy', { policy }); }
  getWagglePolicy() { return this.unary<{ policy?: any }>('GetWagglePolicy', {}); }
  setPolicyProfiles(profiles: any[]) { return this.unary<{ ok: boolean; reason?: string }>('SetPolicyProfiles', { profiles }); }
  listPolicyProfiles() { return this.unary<{ profiles: any[] }>('ListPolicyProfiles', {}); }
  getEffectivePolicy(negotiation_id: string) { return this.unary<{ effective?: any }>('GetEffectivePolicy', { negotiation_id }); }
  submitEvaluation(negotiation_id: string, report: any) { return this.unary<{ accepted: boolean; reason?: string }>('SubmitEvaluation', { negotiation_id, report }); }
  hitlAction(negotiation_id: string, action: string, rationale?: string) { return this.unary<{ ok: boolean; reason?: string }>('HitlAction', { negotiation_id, action, rationale }); }
}

