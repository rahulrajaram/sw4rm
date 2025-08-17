import * as grpc from '@grpc/grpc-js';
import { BaseClient, ClientOptions } from '../internal/baseClient.js';

type ActivityServiceClient = grpc.Client & {
  AppendArtifact(req: { artifact?: any }, meta: grpc.Metadata, opts: grpc.CallOptions, cb: (err: grpc.ServiceError | null, res: { ok: boolean; reason?: string }) => void): void;
  ListArtifacts(req: { negotiation_id: string; kind?: string }, meta: grpc.Metadata, opts: grpc.CallOptions, cb: (err: grpc.ServiceError | null, res: { items: any[] }) => void): void;
};

export class ActivityClient extends BaseClient {
  private client: ActivityServiceClient;
  constructor(opts: ClientOptions) {
    super(opts);
    this.client = this.getServiceClient<ActivityServiceClient>('sw4rm.activity.ActivityService');
  }

  private unary<T>(method: keyof ActivityServiceClient, req: any): Promise<T> {
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

  appendArtifact(artifact: any) { return this.unary<{ ok: boolean; reason?: string }>('AppendArtifact', { artifact }); }
  listArtifacts(negotiation_id: string, kind?: string) { return this.unary<{ items: any[] }>('ListArtifacts', { negotiation_id, kind }); }
}

