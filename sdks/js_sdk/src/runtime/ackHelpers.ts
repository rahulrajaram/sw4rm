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

  // mark SENT in local lifecycle by convention
  ackLifecycle.mark(envelope.message_id, AckStage.RECEIVED, 'sent_waiting_for_received');

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

  return new Promise<void>(async (resolve, reject) => {
    let timeout: NodeJS.Timeout | undefined;
    const cleanup = () => {
      if (timeout) clearTimeout(timeout);
      inboundStream.removeListener('data', onData);
      inboundStream.removeListener('error', onErr);
    };
    const onErr = (err: unknown) => {
      cleanup();
      reject(err);
    };
    inboundStream.on('data', onData);
    inboundStream.on('error', onErr);

    try {
      await router.sendMessage(envelope);
    } catch (e) {
      cleanup();
      return reject(e);
    }

    timeout = setTimeout(() => {
      ackLifecycle.mark(envelope.message_id, AckStage.TIMED_OUT, 'received_timeout');
      cleanup();
      reject(new Error('ACK RECEIVED timeout exceeded'));
    }, receivedTimeoutMs);

    // Resolve when stage advances to at least RECEIVED; caller may await further stages separately
    const checkInterval = setInterval(() => {
      const state = ackLifecycle.get(envelope.message_id);
      if (!state) return;
      if (state.stage === AckStage.RECEIVED || state.stage === AckStage.READ || state.stage === AckStage.FULFILLED) {
        clearInterval(checkInterval);
        if (timeout) clearTimeout(timeout);
        inboundStream.removeListener('data', onData);
        inboundStream.removeListener('error', onErr);
        resolve();
      }
    }, 25);
  });
}

