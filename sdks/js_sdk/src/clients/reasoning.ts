import * as grpc from '@grpc/grpc-js';
import { BaseClient, ClientOptions } from '../internal/baseClient.js';

type ReasoningProxyClient = grpc.Client & {
  CheckParallelism(req: { scope_a: string; scope_b: string }, meta: grpc.Metadata, opts: grpc.CallOptions, cb: (err: grpc.ServiceError | null, res: { confidence_score: number; notes?: string }) => void): void;
  EvaluateDebate(req: { negotiation_id: string; proposal_a: string; proposal_b: string; intensity?: string }, meta: grpc.Metadata, opts: grpc.CallOptions, cb: (err: grpc.ServiceError | null, res: { confidence_score: number; notes?: string }) => void): void;
};

export class ReasoningClient extends BaseClient {
  private client: ReasoningProxyClient;
  constructor(opts: ClientOptions) {
    super(opts);
    this.client = this.getServiceClient<ReasoningProxyClient>('sw4rm.reasoning.ReasoningProxy');
  }

  checkParallelism(scopeA: string, scopeB: string): Promise<{ confidence_score: number; notes?: string }> {
    const meta = this.metadata();
    const opts: grpc.CallOptions = { deadline: this.deadlineFromNow() };
    return this.withRetryUnary(() => new Promise((resolve, reject) => {
      this.client.CheckParallelism({ scope_a: scopeA, scope_b: scopeB }, meta, opts, (err, res) => {
        if (err) return reject(err);
        resolve(res);
      });
    }));
  }

  evaluateDebate(negotiationId: string, proposalA: string, proposalB: string, intensity?: string): Promise<{ confidence_score: number; notes?: string }> {
    const meta = this.metadata();
    const opts: grpc.CallOptions = { deadline: this.deadlineFromNow() };
    return this.withRetryUnary(() => new Promise((resolve, reject) => {
      this.client.EvaluateDebate({ negotiation_id: negotiationId, proposal_a: proposalA, proposal_b: proposalB, intensity }, meta, opts, (err, res) => {
        if (err) return reject(err);
        resolve(res);
      });
    }));
  }
}
