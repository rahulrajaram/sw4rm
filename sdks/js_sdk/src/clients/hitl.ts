import * as grpc from '@grpc/grpc-js';
import { BaseClient, ClientOptions } from '../internal/baseClient.js';

type HitlServiceClient = grpc.Client & {
  Decide(req: HitlInvocation, meta: grpc.Metadata, opts: grpc.CallOptions, cb: (err: grpc.ServiceError | null, res: HitlDecision) => void): void;
};

export interface HitlInvocation {
  reason_type: string; // enum as string from dynamic loader
  context: Uint8Array;
  proposed_actions: string[];
  priority?: number;
}

export interface HitlDecision {
  action: string;
  decision_payload?: Uint8Array;
  rationale?: string;
}

export class HITLClient extends BaseClient {
  private client: HitlServiceClient;
  constructor(opts: ClientOptions) {
    super(opts);
    this.client = this.getServiceClient<HitlServiceClient>('sw4rm.hitl.HitlService');
  }

  async decide(inv: HitlInvocation): Promise<HitlDecision> {
    const meta = this.metadata();
    const opts: grpc.CallOptions = { deadline: this.deadlineFromNow() };
    return this.withRetryUnary(() => new Promise<HitlDecision>((resolve, reject) => {
      this.client.Decide(inv, meta, opts, (err, res) => {
        if (err) return reject(err);
        resolve(res);
      });
    }));
  }
}

