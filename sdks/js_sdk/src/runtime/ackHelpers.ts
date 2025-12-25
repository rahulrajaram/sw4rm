import type * as grpc from '@grpc/grpc-js';
import { RouterClient } from '../clients/router.js';
import { ACKLifecycleManager, AckStage } from '../internal/runtime/ackLifecycle.js';
import { EnvelopeBuilt } from '../internal/envelope.js';

export interface SendWithAckOptions {
  receivedTimeoutMs?: number; // default 10000 per spec
  correlationIdHeader?: string; // default 'x-correlation-id'
}

export type AckExtractor = (env: { msg: EnvelopeBuilt }) => { ackFor?: string; stage?: AckStage } | undefined;

export async function sendMessageWithAck(
  router: RouterClient,
  inboundStream: grpc.ClientReadableStream<{ msg: EnvelopeBuilt }>,
  envelope: EnvelopeBuilt,
  ackLifecycle: ACKLifecycleManager,
  ackExtractor: AckExtractor,
  opts?: SendWithAckOptions,
): Promise<void> {
  const receivedTimeoutMs = opts?.receivedTimeoutMs ?? 10000;

  // Do not prematurely mark RECEIVED; wait for actual ACK or timeout

  const onData = (item: { msg: EnvelopeBuilt }) => {
    const info = ackExtractor(item);
    if (!info) return;
    if (info.ackFor === envelope.message_id) {
      if (info.stage !== undefined) {
        ackLifecycle.mark(envelope.message_id, info.stage);
      } else {
        ackLifecycle.mark(envelope.message_id, AckStage.RECEIVED);
      }
    }
  };

  // Send message first, then set up listeners for ACK
  await router.sendMessage(envelope);

  return new Promise<void>((resolve, reject) => {
    const timeout: NodeJS.Timeout = setTimeout(() => {
      ackLifecycle.mark(envelope.message_id, AckStage.TIMED_OUT, 'received_timeout');
      cleanup();
      reject(new Error('ACK RECEIVED timeout exceeded'));
    }, receivedTimeoutMs);

    const cleanup = () => {
      clearTimeout(timeout);
      inboundStream.removeListener('data', onData);
      inboundStream.removeListener('error', onErr);
    };

    const onErr = (err: unknown) => {
      cleanup();
      reject(err);
    };

    inboundStream.on('data', onData);
    inboundStream.on('error', onErr);

    // Resolve when stage advances to at least RECEIVED; caller may await further stages separately
    const checkInterval = setInterval(() => {
      const state = ackLifecycle.get(envelope.message_id);
      if (!state) return;
      if (state.stage === AckStage.RECEIVED || state.stage === AckStage.READ || state.stage === AckStage.FULFILLED) {
        clearInterval(checkInterval);
        cleanup();
        resolve();
      }
    }, 25);
  });
}
