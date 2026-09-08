import * as grpc from '@grpc/grpc-js';
import { BaseClient, ClientOptions } from '../internal/baseClient.js';
import { EnvelopeBuilt } from '../internal/envelope.js';

type RouterServiceClient = grpc.Client & {
  SendMessage(req: { msg: EnvelopeBuilt }, meta: grpc.Metadata, opts: grpc.CallOptions, cb: (err: grpc.ServiceError | null, res: { accepted: boolean; reason?: string }) => void): void;
  StreamIncoming(req: { agent_id: string }, meta?: grpc.Metadata, opts?: grpc.CallOptions): grpc.ClientReadableStream<StreamItem>;
  AckDelivery(req: DeliveryAckRequest, meta: grpc.Metadata, opts: grpc.CallOptions, cb: (err: grpc.ServiceError | null, res: DeliveryAckResponse) => void): void;
};

export interface SendResult { accepted: boolean; reason?: string }

/** Envelope as decoded off the wire by proto-loader (longs as decimal
 * strings, enums as their NAMES — e.g. `message_type: 'DATA'`, not 2).
 * This is deliberately distinct from {@link EnvelopeBuilt}, which is the
 * SDK-side construction shape with numeric enums; conflating the two was a
 * type lie on the delivery surface. */
export interface EnvelopeWire {
  message_id: string;
  idempotency_token?: string;
  producer_id: string;
  correlation_id: string;
  parent_correlation_id?: string;
  sequence_number: string;
  retry_count: number;
  message_type: string; // MessageType enum NAME
  content_type: string;
  content_length: string; // uint64 → decimal string
  repo_id?: string;
  worktree_id?: string;
  hlc_timestamp?: string;
  ttl_ms?: string;
  timestamp?: { seconds: number | string; nanos: number };
  payload?: Uint8Array;
  state: string; // EnvelopeState enum NAME
}

/** Item yielded by Router.StreamIncoming. `seq` is lossless because the
 * underlying proto-loader represents int64 values as strings. */
export interface StreamItem {
  msg: EnvelopeWire;
  seq: string;
}

export interface DeliveryAckRequest {
  agent_id: string;
  seq: string;
  message_id: string;
  outcome: 'DELIVERY_ACK_OUTCOME_DELIVERED' | 'DELIVERY_ACK_OUTCOME_PERMANENT_FAILURE';
}

export interface DeliveryAckResponse {
  recorded: boolean;
}

export type DeliveryAckSeq = string | number | bigint;

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

  streamIncoming(agentId: string, meta?: grpc.Metadata, options?: grpc.CallOptions): grpc.ClientReadableStream<StreamItem> {
    const m = this.metadata(meta);
    return this.client.StreamIncoming({ agent_id: agentId }, m, options);
  }

  /** Acknowledge a StreamItem and release its pending router row. */
  async ackDelivery(
    agentId: string,
    seq: DeliveryAckSeq,
    messageId = '',
    permanentFailure = false,
  ): Promise<DeliveryAckResponse> {
    if (typeof seq === 'number' && !Number.isSafeInteger(seq)) {
      throw new TypeError('numeric seq must be a safe integer; use a string or bigint for int64 values');
    }
    const seqValue = String(seq);
    if (!/^\d+$/.test(seqValue) || BigInt(seqValue) <= 0n || BigInt(seqValue) > 9223372036854775807n) {
      throw new TypeError('seq must be a positive int64');
    }
    const meta = this.metadata();
    const request: DeliveryAckRequest = {
      agent_id: agentId,
      seq: seqValue,
      message_id: messageId,
      outcome: permanentFailure
        ? 'DELIVERY_ACK_OUTCOME_PERMANENT_FAILURE'
        : 'DELIVERY_ACK_OUTCOME_DELIVERED',
    };
    const callOpts: grpc.CallOptions = { deadline: this.deadlineFromNow() };
    return this.withRetryUnary<DeliveryAckResponse>(() => new Promise((resolve, reject) => {
      this.client.AckDelivery(request, meta, callOpts, (err, res) => {
        if (err) return reject(err);
        resolve({ recorded: !!res?.recorded });
      });
    }), 'sw4rm.router.AckDelivery', meta);
  }

  /** Convenience form for acknowledging a streamed item. */
  ackStreamItem(
    agentId: string,
    item: Pick<StreamItem, 'seq' | 'msg'>,
    permanentFailure = false,
  ): Promise<DeliveryAckResponse> {
    return this.ackDelivery(agentId, item.seq, item.msg?.message_id ?? '', permanentFailure);
  }
}
