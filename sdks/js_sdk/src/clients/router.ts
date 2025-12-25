import * as grpc from '@grpc/grpc-js';
import { BaseClient, ClientOptions } from '../internal/baseClient.js';
import { EnvelopeBuilt } from '../internal/envelope.js';

type RouterServiceClient = grpc.Client & {
  SendMessage(req: { msg: EnvelopeBuilt }, meta: grpc.Metadata, opts: grpc.CallOptions, cb: (err: grpc.ServiceError | null, res: { accepted: boolean; reason?: string }) => void): void;
  StreamIncoming(req: { agent_id: string }, meta?: grpc.Metadata): grpc.ClientReadableStream<{ msg: EnvelopeBuilt }>;
};

export interface SendResult { accepted: boolean; reason?: string }

export class RouterClient extends BaseClient {
  private client: RouterServiceClient;

  constructor(opts: ClientOptions) {
    super(opts);
    this.client = this.getServiceClient<RouterServiceClient>('sw4rm.router.RouterService');
  }

  async sendMessage(envelope: EnvelopeBuilt): Promise<SendResult> {
    const meta = this.metadata();
    // Propagate correlation at transport level per spec (§5)
    if (envelope.correlation_id && !meta.get('x-correlation-id').length) meta.set('x-correlation-id', envelope.correlation_id);
    const callOpts: grpc.CallOptions = { deadline: this.deadlineFromNow() };
    return this.withRetryUnary<SendResult>(() => new Promise((resolve, reject) => {
      this.client.SendMessage({ msg: envelope }, meta, callOpts, (err, res) => {
        if (err) return reject(err);
        resolve({ accepted: !!res?.accepted, reason: res?.reason });
      });
    }), 'sw4rm.router.SendMessage', meta);
  }

  streamIncoming(agentId: string, meta?: grpc.Metadata): grpc.ClientReadableStream<{ msg: EnvelopeBuilt }> {
    const m = this.metadata(meta);
    return this.client.StreamIncoming({ agent_id: agentId }, m);
  }
}
