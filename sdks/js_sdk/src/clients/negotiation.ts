import * as grpc from '@grpc/grpc-js';
import { BaseClient, ClientOptions } from '../internal/baseClient.js';

type NegotiationServiceClient = grpc.Client & {
  Open(req: NegotiationOpen, meta: grpc.Metadata, opts: grpc.CallOptions, cb: (err: grpc.ServiceError | null, res: Empty) => void): void;
  Propose(req: Proposal, meta: grpc.Metadata, opts: grpc.CallOptions, cb: (err: grpc.ServiceError | null, res: Empty) => void): void;
  Counter(req: CounterProposal, meta: grpc.Metadata, opts: grpc.CallOptions, cb: (err: grpc.ServiceError | null, res: Empty) => void): void;
  Evaluate(req: Evaluation, meta: grpc.Metadata, opts: grpc.CallOptions, cb: (err: grpc.ServiceError | null, res: Empty) => void): void;
  Decide(req: Decision, meta: grpc.Metadata, opts: grpc.CallOptions, cb: (err: grpc.ServiceError | null, res: Empty) => void): void;
  Abort(req: AbortRequest, meta: grpc.Metadata, opts: grpc.CallOptions, cb: (err: grpc.ServiceError | null, res: Empty) => void): void;
};

export interface Empty {}
export interface NegotiationOpen {
  negotiation_id: string;
  correlation_id: string;
  topic: string;
  participants: string[];
  intensity: string; // enum as string via dynamic loader
  debate_timeout?: { seconds: number | string; nanos?: number };
}

export interface Proposal { negotiation_id: string; from_agent: string; content_type: string; payload: Uint8Array }
export interface CounterProposal { negotiation_id: string; from_agent: string; content_type: string; payload: Uint8Array }
export interface Evaluation { negotiation_id: string; from_agent: string; confidence_score?: number; notes?: string }
export interface Decision { negotiation_id: string; decided_by: string; content_type: string; result: Uint8Array }
export interface AbortRequest { negotiation_id: string; reason?: string }

export class NegotiationClient extends BaseClient {
  private client: NegotiationServiceClient;
  constructor(opts: ClientOptions) {
    super(opts);
    this.client = this.getServiceClient<NegotiationServiceClient>('sw4rm.negotiation.NegotiationService');
  }

  private unary<T>(method: keyof NegotiationServiceClient, req: any): Promise<T> {
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

  open(req: NegotiationOpen) { return this.unary<Empty>('Open', req); }
  propose(req: Proposal) { return this.unary<Empty>('Propose', req); }
  counter(req: CounterProposal) { return this.unary<Empty>('Counter', req); }
  evaluate(req: Evaluation) { return this.unary<Empty>('Evaluate', req); }
  decide(req: Decision) { return this.unary<Empty>('Decide', req); }
  abort(req: AbortRequest) { return this.unary<Empty>('Abort', req); }
}

