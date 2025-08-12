import * as grpc from '@grpc/grpc-js';
import { BaseClient, ClientOptions } from '../internal/baseClient.js';

type LoggingServiceClient = grpc.Client & {
  Ingest(req: LogEvent, meta: grpc.Metadata, opts: grpc.CallOptions, cb: (err: grpc.ServiceError | null, res: { ok: boolean }) => void): void;
};

export interface Timestamp { seconds: number | string; nanos?: number }
export interface LogEvent {
  ts: Timestamp;
  correlation_id: string;
  agent_id: string;
  event_type: string;
  level: string;
  details_json: string;
}

export class LoggingClient extends BaseClient {
  private client: LoggingServiceClient;
  constructor(opts: ClientOptions) {
    super(opts);
    this.client = this.getServiceClient<LoggingServiceClient>('sw4rm.logging.LoggingService');
  }

  async ingest(evt: LogEvent): Promise<boolean> {
    const meta = this.metadata();
    const opts: grpc.CallOptions = { deadline: this.deadlineFromNow() };
    return this.withRetryUnary(() => new Promise<boolean>((resolve, reject) => {
      this.client.Ingest(evt, meta, opts, (err, res) => {
        if (err) return reject(err);
        resolve(!!res?.ok);
      });
    }));
  }
}

