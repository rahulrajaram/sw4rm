import { EventEmitter } from 'node:events';
import type * as grpc from '@grpc/grpc-js';
import { RouterClient } from '../clients/router.js';

export interface ResilientOptions {
  initialBackoffMs?: number;
  maxBackoffMs?: number;
  multiplier?: number;
}

export function createResilientIncomingStream(
  router: RouterClient,
  agentId: string,
  opts?: ResilientOptions,
): EventEmitter {
  const emitter = new EventEmitter();
  let backoff = opts?.initialBackoffMs ?? 500;
  const maxBackoff = opts?.maxBackoffMs ?? 8000;
  const mult = opts?.multiplier ?? 2;
  let stopped = false;
  let current: grpc.ClientReadableStream<any> | null = null;

  const start = () => {
    if (stopped) return;
    const stream = router.streamIncoming(agentId);
    current = stream;
    stream.on('data', (msg) => emitter.emit('data', msg));
    stream.on('error', async () => {
      if (stopped) return;
      await new Promise(r => setTimeout(r, backoff));
      backoff = Math.min(maxBackoff, backoff * mult);
      emitter.emit('reconnecting', backoff);
      start();
    });
    stream.on('end', async () => {
      if (stopped) return;
      await new Promise(r => setTimeout(r, backoff));
      backoff = Math.min(maxBackoff, backoff * mult);
      emitter.emit('reconnecting', backoff);
      start();
    });
  };

  // public controls
  // @ts-expect-error augment emitter
  emitter.stop = () => {
    stopped = true;
    try {
      if (current && typeof (current as any).cancel === 'function') {
        (current as any).cancel();
      }
    } catch {
      // Ignore cancel errors
    }
    current = null;
  };

  start();
  return emitter;
}
