import { describe, it, expect } from 'vitest';
import { EventEmitter } from 'node:events';
import { createResilientIncomingStream } from '../src/runtime/streams.js';
import * as grpc from '@grpc/grpc-js';
import * as protoLoader from '@grpc/proto-loader';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { RouterClient } from '../src/clients/router.js';

class FakeRouter {
  calls = 0;
  streamIncoming() {
    this.calls++;
    const emitter = new EventEmitter();
    // First call errors, second call emits data
    if (this.calls === 1) {
      setTimeout(() => emitter.emit('error', new Error('boom')), 5);
    } else {
      setTimeout(() => emitter.emit('data', { msg: { message_id: 'm1' } }), 10);
    }
    // minimal API surface used by consumer
    // @ts-expect-error compatible enough for test
    return emitter;
  }
}

describe('createResilientIncomingStream', () => {
  it('reconnects on error and emits data', async () => {
    const router = new FakeRouter() as any;
    const emitter = createResilientIncomingStream(router, 'agent-1', { initialBackoffMs: 1, maxBackoffMs: 2 });
    let reconnected = false;
    let gotData = false;
    emitter.on('reconnecting', () => { reconnected = true; });
    await new Promise<void>((resolve) => {
      emitter.on('data', (_: any) => { gotData = true; resolve(); });
    });
    expect(reconnected).toBe(true);
    expect(gotData).toBe(true);
  });
});

describe('Router delivery ACK wire contract', () => {
  it('round-trips StreamItem.seq losslessly and acknowledges by seq', async () => {
    const here = path.dirname(fileURLToPath(import.meta.url));
    const protos = path.resolve(here, '../../../protos');
    const definition = protoLoader.loadSync(
      [path.join(protos, 'common.proto'), path.join(protos, 'router.proto')],
      { keepCase: true, longs: String, enums: String, defaults: true, oneofs: true, includeDirs: [protos] },
    );
    const loaded = grpc.loadPackageDefinition(definition) as any;
    const server = new grpc.Server();
    let ackRequest: any;
    let streamCall: grpc.ServerWritableStream<any, any> | undefined;
    server.addService(loaded.sw4rm.router.RouterService.service, {
      StreamIncoming(call: grpc.ServerWritableStream<any, any>) {
        streamCall = call;
        call.write({
          msg: { message_id: 'wire-message', producer_id: 'producer', message_type: 2, payload: Buffer.from('hello') },
          seq: '9007199254740993',
        });
      },
      AckDelivery(call: grpc.ServerUnaryCall<any, any>, callback: grpc.sendUnaryData<any>) {
        ackRequest = call.request;
        callback(null, { recorded: true });
      },
    });

    const port = await new Promise<number>((resolve, reject) => {
      server.bindAsync('127.0.0.1:0', grpc.ServerCredentials.createInsecure(), (error, boundPort) => {
        if (error) reject(error);
        else resolve(boundPort);
      });
    });
    const router = new RouterClient({ address: `127.0.0.1:${port}`, deadlineMs: 2_000 });
    const stream = router.streamIncoming('consumer');
    const item = await new Promise<any>((resolve, reject) => {
      stream.once('data', resolve);
      stream.once('error', reject);
    });
    expect(item.seq).toBe('9007199254740993');
    // StreamItem.msg is the WIRE shape: enums decode to their names and
    // uint64s to decimal strings, never the numeric construction types.
    expect(item.msg.message_type).toBe('DATA');
    expect(typeof item.msg.message_type).toBe('string');
    expect(item.msg.state).toBe('ENVELOPE_STATE_UNSPECIFIED');
    expect(item.msg.sequence_number).toBe('0');
    expect(item.msg.retry_count).toBe(0);
    expect(item.msg.producer_id).toBe('producer');
    const ack = await router.ackStreamItem('consumer', item, true);
    expect(ack).toEqual({ recorded: true });
    expect(ackRequest).toMatchObject({
      agent_id: 'consumer',
      seq: '9007199254740993',
      message_id: 'wire-message',
      outcome: 'DELIVERY_ACK_OUTCOME_PERMANENT_FAILURE',
    });
    streamCall?.end();
    stream.cancel();
    await new Promise<void>((resolve) => server.tryShutdown(() => resolve()));
  });
});


describe('delivery sequence validation', () => {
  it('rejects rounded numeric sequences and values outside signed int64', async () => {
    const router = new RouterClient({ address: '127.0.0.1:1' });
    for (const seq of [Number.MAX_SAFE_INTEGER + 1, '9223372036854775808', '-1', '0', '1.5']) {
      await expect(router.ackDelivery('consumer', seq)).rejects.toThrow(TypeError);
    }
  });
});
